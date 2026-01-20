#!/usr/bin/env bash
################################################################################
# UASF - Universal Attack Simulation Framework
# Version: 1.0.0
# 
# A production-grade Red Team attack simulation framework for validating
# WAAP/WAF security controls through safe, controlled attack scenarios.
#
# Copyright (c) 2026 - Red Team Engineering
# Licensed for authorized security testing only.
################################################################################

set -euo pipefail

################################################################################
# CONSTANTS AND CONFIGURATION
################################################################################

readonly UASF_VERSION="1.0.0"
readonly UASF_NAME="UASF"

# Default configuration
DEFAULT_RPS=5
DEFAULT_CONCURRENCY=1
DEFAULT_TIMEOUT=30

# Result classifications
readonly RESULT_BLOCKED="BLOCKED"
readonly RESULT_ALLOWED="ALLOWED"
readonly RESULT_CHALLENGED="CHALLENGED"
readonly RESULT_INCONCLUSIVE="INCONCLUSIVE"

# Color codes for output (optional, fallback to no color if not tty)
if [[ -t 1 ]]; then
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_RESET='\033[0m'
else
    readonly COLOR_RED=''
    readonly COLOR_GREEN=''
    readonly COLOR_YELLOW=''
    readonly COLOR_BLUE=''
    readonly COLOR_RESET=''
fi

################################################################################
# GLOBAL VARIABLES
################################################################################

# CLI arguments
TARGET_URL=""
SCENARIO_DIR=""
OUTPUT_DIR=""
EVIDENCE_DIR=""
JSON_OUTPUT=""
SCOPE_REGEX=""
RPS=$DEFAULT_RPS
CONCURRENCY=$DEFAULT_CONCURRENCY
TIMEOUT=$DEFAULT_TIMEOUT

# Runtime state
TOTAL_SCENARIOS=0
TOTAL_REQUESTS=0
START_TIME=""
SCENARIO_RESULTS=()
RUNTIME_STATE_DIR=""

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Print colored message to stderr
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} [$timestamp] $message" >&2
            ;;
        WARN)
            echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} [$timestamp] $message" >&2
            ;;
        ERROR)
            echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} [$timestamp] $message" >&2
            ;;
        SUCCESS)
            echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} [$timestamp] $message" >&2
            ;;
        *)
            echo "[$timestamp] $message" >&2
            ;;
    esac
}

# Fatal error - log and exit
die() {
    log ERROR "$@"
    exit 1
}

# Get portable timestamp (works on both Linux and macOS)
# Includes random component to avoid collisions
get_timestamp() {
    echo "$(date '+%Y%m%d_%H%M%S')_$$_${RANDOM}"
}

# Get ISO 8601 timestamp
get_iso_timestamp() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# URL encode a string
url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o

    for ((pos=0; pos<strlen; pos++)); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9])
                o="${c}"
                ;;
            *)
                printf -v o '%%%02x' "'$c"
                ;;
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# Validate URL format
is_valid_url() {
    local url="$1"
    if [[ "$url" =~ ^https?:// ]]; then
        return 0
    else
        return 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required dependencies
check_dependencies() {
    local missing=()
    
    for cmd in curl jq sed awk grep date df; do
        if ! command_exists "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
}

# Check available disk space (in KB)
check_disk_space() {
    local directory="$1"
    local required_kb="$2"
    local available_kb
    
    # Get available space (works on both Linux and macOS)
    if df -k "$directory" >/dev/null 2>&1; then
        available_kb=$(df -k "$directory" | awk 'NR==2 {print $4}')
        
        if [[ "$available_kb" -lt "$required_kb" ]]; then
            log WARN "Low disk space: ${available_kb}KB available, ${required_kb}KB recommended"
            return 1
        fi
    else
        log WARN "Unable to check disk space for: $directory"
    fi
    
    return 0
}

# Validate JSON scenario file
validate_scenario() {
    local file="$1"
    
    # Check file exists and is readable
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        log ERROR "Scenario file not readable: $file"
        return 1
    fi
    
    # Validate JSON syntax and required fields
    if ! jq -e '.name and .description and .steps' "$file" >/dev/null 2>&1; then
        log ERROR "Invalid scenario schema (missing name/description/steps): $file"
        return 1
    fi
    
    # Validate steps array
    local step_count
    step_count=$(jq -r '.steps | length' "$file" 2>/dev/null || echo "0")
    
    if [[ "$step_count" -eq 0 ]]; then
        log ERROR "Scenario has no steps: $file"
        return 1
    fi
    
    return 0
}

# Initialize audit log
init_audit_log() {
    local audit_file="${OUTPUT_DIR}/audit.log"
    
    {
        echo "==================================================================="
        echo "UASF EXECUTION AUDIT LOG"
        echo "==================================================================="
        echo "Framework: ${UASF_NAME} v${UASF_VERSION}"
        echo "Start Time: $(get_iso_timestamp)"
        echo "User: ${USER:-unknown}"
        echo "Hostname: $(hostname 2>/dev/null || echo 'unknown')"
        echo "Working Directory: $(pwd)"
        echo "PID: $$"
        echo "Command: $0 $@"
        echo ""
        echo "Configuration:"
        echo "  Target: ${TARGET_URL}"
        echo "  Scenarios: ${SCENARIO_DIR}"
        echo "  Output: ${OUTPUT_DIR}"
        echo "  Evidence: ${EVIDENCE_DIR}"
        echo "  Scope Regex: ${SCOPE_REGEX}"
        echo "  RPS Limit: ${RPS}"
        echo "  Timeout: ${TIMEOUT}s"
        echo "==================================================================="
        echo ""
    } > "$audit_file"
    
    log INFO "Audit log initialized: $audit_file"
}

# Append to audit log
audit_log() {
    local audit_file="${OUTPUT_DIR}/audit.log"
    echo "[$(get_iso_timestamp)] $*" >> "$audit_file" 2>/dev/null || true
}

# Cleanup handler for interrupts
cleanup_handler() {
    local exit_code=$?
    
    log WARN "Execution interrupted (exit code: $exit_code)"
    audit_log "INTERRUPTED: Execution terminated with exit code $exit_code"
    
    # Try to generate partial results if possible
    if [[ -n "$OUTPUT_DIR" ]] && [[ -n "$EVIDENCE_DIR" ]]; then
        log INFO "Attempting to save partial results..."
        audit_log "Generating partial results before exit"
        
        # Count requests from evidence files
        TOTAL_REQUESTS=$(find "$EVIDENCE_DIR" -name "*_request.txt" 2>/dev/null | wc -l | tr -d ' ')
        
        # Generate reports if we have any results
        if [[ ${#SCENARIO_RESULTS[@]} -gt 0 ]]; then
            generate_json_report 2>/dev/null || true
            generate_markdown_summary 2>/dev/null || true
        fi
    fi
    
    exit $exit_code
}

################################################################################
# CLI ARGUMENT PARSING
################################################################################

usage() {
    cat <<EOF
${UASF_NAME} v${UASF_VERSION} - Universal Attack Simulation Framework

USAGE:
    $0 run [OPTIONS]

DESCRIPTION:
    Execute safe Red Team attack simulations to validate WAAP/WAF controls.
    
    This framework is designed for AUTHORIZED security testing only.
    All scenarios must be non-destructive and pre-approved.

OPTIONS:
    --target <url>              Target base URL (required)
    --scenarios <directory>     Directory containing scenario JSON files (required)
    --out <directory>           Output directory for reports (required)
    --evidence <directory>      Directory for evidence files (required)
    --json <file>               JSON results output file (required)
    --scope-regex <regex>       Regex to enforce request scope (required)
    --rps <number>              Requests per second limit (default: $DEFAULT_RPS)
    --concurrency <number>      Concurrent workers (default: $DEFAULT_CONCURRENCY)
    --timeout <seconds>         HTTP timeout in seconds (default: $DEFAULT_TIMEOUT)
    --help                      Show this help message

EXAMPLES:
    # Basic execution
    $0 run \\
        --target https://example.com \\
        --scenarios ./scenarios \\
        --out ./output \\
        --evidence ./evidence \\
        --json ./results.json \\
        --scope-regex "^https://example\\.com"

    # With rate limiting
    $0 run \\
        --target https://api.example.com \\
        --scenarios ./scenarios \\
        --out ./output \\
        --evidence ./evidence \\
        --json ./results.json \\
        --scope-regex "^https://api\\.example\\.com" \\
        --rps 2 \\
        --timeout 60

SCENARIO FORMAT:
    Scenarios are JSON files with the following structure:
    
    {
        "name": "Scenario Name",
        "description": "Detailed description",
        "steps": [
            {
                "method": "GET",
                "path": "/api/endpoint",
                "headers": {"X-Custom": "value"},
                "body": "",
                "repeat": 1,
                "sleep_ms": 0,
                "expect_http_codes": [200, 403]
            }
        ]
    }

LEGAL WARNING:
    This tool is designed for AUTHORIZED security testing only.
    Unauthorized use is illegal and unethical.
    Always obtain explicit written permission before testing.

EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi
    
    local command="$1"
    shift
    
    if [[ "$command" == "--help" ]] || [[ "$command" == "-h" ]]; then
        usage
        exit 0
    fi
    
    if [[ "$command" != "run" ]]; then
        die "Unknown command: $command. Use 'run' or '--help'."
    fi
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --target)
                TARGET_URL="$2"
                shift 2
                ;;
            --scenarios)
                SCENARIO_DIR="$2"
                shift 2
                ;;
            --out)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --evidence)
                EVIDENCE_DIR="$2"
                shift 2
                ;;
            --json)
                JSON_OUTPUT="$2"
                shift 2
                ;;
            --scope-regex)
                SCOPE_REGEX="$2"
                shift 2
                ;;
            --rps)
                RPS="$2"
                shift 2
                ;;
            --concurrency)
                CONCURRENCY="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
    
    # Validate required arguments
    [[ -z "$TARGET_URL" ]] && die "Missing required argument: --target"
    [[ -z "$SCENARIO_DIR" ]] && die "Missing required argument: --scenarios"
    [[ -z "$OUTPUT_DIR" ]] && die "Missing required argument: --out"
    [[ -z "$EVIDENCE_DIR" ]] && die "Missing required argument: --evidence"
    [[ -z "$JSON_OUTPUT" ]] && die "Missing required argument: --json"
    [[ -z "$SCOPE_REGEX" ]] && die "Missing required argument: --scope-regex"
    
    # Validate target URL
    is_valid_url "$TARGET_URL" || die "Invalid target URL: $TARGET_URL"
    
    # Validate scenario directory exists
    [[ -d "$SCENARIO_DIR" ]] || die "Scenario directory not found: $SCENARIO_DIR"
    
    # Create output directories if they don't exist
    mkdir -p "$OUTPUT_DIR" || die "Failed to create output directory: $OUTPUT_DIR"
    mkdir -p "$EVIDENCE_DIR" || die "Failed to create evidence directory: $EVIDENCE_DIR"
    
    # Create runtime state directory for counters
    RUNTIME_STATE_DIR="${EVIDENCE_DIR}/.runtime"
    mkdir -p "$RUNTIME_STATE_DIR" || die "Failed to create runtime state directory"
    
    # Check available disk space (require at least 100MB)
    check_disk_space "$EVIDENCE_DIR" 102400 || log WARN "Continuing despite low disk space"
    
    # Validate numeric arguments
    [[ "$RPS" =~ ^[0-9]+$ ]] || die "Invalid RPS value: $RPS"
    [[ "$CONCURRENCY" =~ ^[0-9]+$ ]] || die "Invalid concurrency value: $CONCURRENCY"
    [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || die "Invalid timeout value: $TIMEOUT"
    
    # Validate scope-regex is valid regex
    if ! echo "test" | grep -qE "$SCOPE_REGEX" 2>/dev/null && ! echo "test" | grep -qvE "$SCOPE_REGEX" 2>/dev/null; then
        log WARN "Scope regex may be invalid: $SCOPE_REGEX"
    fi
    
    log INFO "Configuration validated successfully"
    
    # Initialize audit log
    init_audit_log "$@"
}

################################################################################
# SCOPE VALIDATION
################################################################################

validate_scope() {
    local url="$1"
    
    if [[ "$url" =~ $SCOPE_REGEX ]]; then
        return 0
    else
        log ERROR "Scope validation FAILED: $url does not match regex: $SCOPE_REGEX"
        audit_log "SCOPE_VIOLATION: $url"
        return 1
    fi
}

################################################################################
# HTTP REQUEST ENGINE
################################################################################

# Execute HTTP request and store evidence
# Returns: HTTP status code
execute_request() {
    local method="$1"
    local url="$2"
    local headers_json="$3"
    local body="$4"
    local timestamp
    local request_file
    local response_file
    local headers_file
    local status_code
    local curl_args=()
    
    timestamp=$(get_timestamp)
    request_file="${EVIDENCE_DIR}/${timestamp}_request.txt"
    response_file="${EVIDENCE_DIR}/${timestamp}_response.txt"
    headers_file="${EVIDENCE_DIR}/${timestamp}_headers.txt"
    
    # Validate scope before making request
    validate_scope "$url" || die "Request blocked: out of scope"
    
    # Build curl arguments
    curl_args=(
        -X "$method"
        -s
        -w "%{http_code}"
        -o "$response_file"
        -D "$headers_file"
        --max-time "$TIMEOUT"
        --connect-timeout 10
        --max-filesize 10485760
    )
    
    # Add headers if provided
    if [[ -n "$headers_json" ]] && [[ "$headers_json" != "null" ]]; then
        while IFS='=' read -r key value; do
            if [[ -n "$key" ]]; then
                curl_args+=(-H "$key: $value")
            fi
        done < <(echo "$headers_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
    fi
    
    # Add body if provided
    if [[ -n "$body" ]] && [[ "$body" != "null" ]] && [[ "$body" != "" ]]; then
        curl_args+=(-d "$body")
    fi
    
    # Store request details
    {
        echo "=== REQUEST ==="
        echo "Timestamp: $(get_iso_timestamp)"
        echo "Method: $method"
        echo "URL: $url"
        echo ""
        echo "=== HEADERS ==="
        if [[ -n "$headers_json" ]] && [[ "$headers_json" != "null" ]]; then
            echo "$headers_json" | jq -r 'to_entries[] | "\(.key): \(.value)"'
        fi
        echo ""
        if [[ -n "$body" ]] && [[ "$body" != "null" ]] && [[ "$body" != "" ]]; then
            echo "=== BODY ==="
            echo "$body"
        fi
    } > "$request_file"
    
    # Execute request
    log INFO "Executing: $method $url"
    status_code=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo "000")
    
    # Increment request counter (file-based to persist across subshells)
    echo "1" >> "${RUNTIME_STATE_DIR}/request_count.txt"
    
    # Store complete response with metadata (prepend to response file)
    local temp_response="${response_file}.tmp"
    {
        echo "=== RESPONSE ==="
        echo "Timestamp: $(get_iso_timestamp)"
        echo "Status Code: $status_code"
        echo ""
        echo "=== RESPONSE HEADERS ==="
        if [[ -f "$headers_file" ]]; then
            cat "$headers_file"
        fi
        echo ""
        echo "=== RESPONSE BODY ==="
        if [[ -f "$response_file" ]]; then
            cat "$response_file"
        fi
    } > "$temp_response"
    
    # Replace response file with complete version
    mv "$temp_response" "$response_file"
    
    # Return status code
    echo "$status_code"
}

################################################################################
# RATE LIMITING
################################################################################

# Sleep to maintain RPS limit
rate_limit() {
    if [[ "$RPS" -gt 0 ]]; then
        local sleep_time
        sleep_time=$(awk "BEGIN {print 1.0 / $RPS}")
        sleep "$sleep_time"
    fi
}

################################################################################
# RESULT CLASSIFICATION
################################################################################

classify_result() {
    local status_code="$1"
    local response_body="$2"
    local expect_codes="$3"
    
    # Check if status code is in expected codes
    local is_expected=0
    if [[ -n "$expect_codes" ]] && [[ "$expect_codes" != "null" ]]; then
        while IFS= read -r code; do
            if [[ "$status_code" == "$code" ]]; then
                is_expected=1
                break
            fi
        done < <(echo "$expect_codes" | jq -r '.[]')
    fi
    
    # Classification logic
    case "$status_code" in
        403|406|418)
            # Blocked by WAF/WAAP
            echo "$RESULT_BLOCKED"
            ;;
        429|503)
            # Rate limited or challenged
            echo "$RESULT_CHALLENGED"
            ;;
        200|201|202|204)
            # Successful response - check for WAF signatures in body
            if echo "$response_body" | grep -qiE '(access.denied|blocked|firewall|security|waf|captcha)'; then
                echo "$RESULT_CHALLENGED"
            else
                echo "$RESULT_ALLOWED"
            fi
            ;;
        000)
            # Connection failed or timeout
            echo "$RESULT_INCONCLUSIVE"
            ;;
        *)
            # Unexpected status code
            if [[ $is_expected -eq 1 ]]; then
                echo "$RESULT_BLOCKED"
            else
                echo "$RESULT_INCONCLUSIVE"
            fi
            ;;
    esac
}

################################################################################
# SCENARIO EXECUTION
################################################################################

execute_scenario() {
    local scenario_file="$1"
    local scenario_name
    local scenario_desc
    local steps
    local step_count
    local evidence_files=()
    local results=()
    local final_status="$RESULT_INCONCLUSIVE"
    
    log INFO "Loading scenario: $scenario_file"
    
    # Validate scenario before execution
    if ! validate_scenario "$scenario_file"; then
        log ERROR "Skipping invalid scenario: $scenario_file"
        audit_log "SCENARIO_FAILED_VALIDATION: $scenario_file"
        return 1
    fi
    
    # Parse scenario JSON with error handling
    scenario_name=$(jq -r '.name // "Unknown"' "$scenario_file" 2>/dev/null || echo "Unknown")
    scenario_desc=$(jq -r '.description // ""' "$scenario_file" 2>/dev/null || echo "")
    step_count=$(jq '.steps | length' "$scenario_file" 2>/dev/null || echo "0")
    
    if [[ "$step_count" -eq 0 ]]; then
        log ERROR "No steps found in scenario: $scenario_file"
        return 1
    fi
    
    log INFO "Executing scenario: $scenario_name ($step_count steps)"
    
    # Execute each step
    for ((i=0; i<step_count; i++)); do
        local method
        local path
        local headers
        local body
        local repeat
        local sleep_ms
        local expect_codes
        local full_url
        local status_code
        local response_body
        local step_result
        
        # Parse step with error handling
        method=$(jq -r ".steps[$i].method // \"GET\"" "$scenario_file" 2>/dev/null || echo "GET")
        path=$(jq -r ".steps[$i].path // \"/\"" "$scenario_file" 2>/dev/null || echo "/")
        headers=$(jq -c ".steps[$i].headers // {}" "$scenario_file" 2>/dev/null || echo "{}")
        body=$(jq -r ".steps[$i].body // \"\"" "$scenario_file" 2>/dev/null || echo "")
        repeat=$(jq -r ".steps[$i].repeat // 1" "$scenario_file" 2>/dev/null || echo "1")
        sleep_ms=$(jq -r ".steps[$i].sleep_ms // 0" "$scenario_file" 2>/dev/null || echo "0")
        expect_codes=$(jq -c ".steps[$i].expect_http_codes // []" "$scenario_file" 2>/dev/null || echo "[]")
        
        # Validate critical fields
        if [[ -z "$method" ]] || [[ -z "$path" ]]; then
            log WARN "Step $((i+1)) has invalid method or path, skipping"
            continue
        fi
        
        # Build full URL
        full_url="${TARGET_URL}${path}"
        
        log INFO "Step $((i+1))/$step_count: $method $path (repeat: $repeat)"
        
        # Execute request (with repeats)
        for ((r=0; r<repeat; r++)); do
            # Rate limiting
            rate_limit
            
            # Execute request
            status_code=$(execute_request "$method" "$full_url" "$headers" "$body")
            
            # Read response body for classification (from most recent response file)
            response_body=""
            latest_response=$(ls -t "${EVIDENCE_DIR}"/*_response.txt 2>/dev/null | head -1)
            if [[ -f "$latest_response" ]]; then
                # Extract body section (limit to first 200 lines for performance)
                # This is sufficient for WAF signature detection
                response_body=$(awk '/^=== RESPONSE BODY ===$/{flag=1;next}flag{print;if(++count>=200)exit}' "$latest_response" 2>/dev/null || echo "")
            fi
            
            # Classify result
            step_result=$(classify_result "$status_code" "$response_body" "$expect_codes")
            results+=("$step_result")
            
            log INFO "Result: $status_code -> $step_result"
            
            # Sleep if configured
            if [[ "$sleep_ms" -gt 0 ]]; then
                local sleep_sec
                sleep_sec=$(awk "BEGIN {print $sleep_ms / 1000.0}")
                sleep "$sleep_sec"
            fi
        done
    done
    
    # Determine final scenario status
    # If any step was ALLOWED, scenario is ALLOWED
    # If all steps were BLOCKED, scenario is BLOCKED
    # If any step was CHALLENGED, scenario is CHALLENGED
    # Otherwise INCONCLUSIVE
    
    local allowed_count=0
    local blocked_count=0
    local challenged_count=0
    local inconclusive_count=0
    
    for result in "${results[@]}"; do
        case "$result" in
            "$RESULT_ALLOWED") ((allowed_count++)) ;;
            "$RESULT_BLOCKED") ((blocked_count++)) ;;
            "$RESULT_CHALLENGED") ((challenged_count++)) ;;
            "$RESULT_INCONCLUSIVE") ((inconclusive_count++)) ;;
        esac
    done
    
    if [[ $allowed_count -gt 0 ]]; then
        final_status="$RESULT_ALLOWED"
    elif [[ $blocked_count -eq ${#results[@]} ]]; then
        final_status="$RESULT_BLOCKED"
    elif [[ $challenged_count -gt 0 ]]; then
        final_status="$RESULT_CHALLENGED"
    else
        final_status="$RESULT_INCONCLUSIVE"
    fi
    
    log SUCCESS "Scenario completed: $scenario_name -> $final_status"
    audit_log "SCENARIO_COMPLETE: $scenario_name -> $final_status ($step_count steps)"
    
    # Store scenario result
    local scenario_result
    scenario_result=$(jq -n \
        --arg name "$scenario_name" \
        --arg desc "$scenario_desc" \
        --arg status "$final_status" \
        --argjson steps "$step_count" \
        --argjson allowed "$allowed_count" \
        --argjson blocked "$blocked_count" \
        --argjson challenged "$challenged_count" \
        --argjson inconclusive "$inconclusive_count" \
        '{
            scenario: $name,
            description: $desc,
            status: $status,
            steps_executed: $steps,
            results: {
                allowed: $allowed,
                blocked: $blocked,
                challenged: $challenged,
                inconclusive: $inconclusive
            }
        }')
    
    SCENARIO_RESULTS+=("$scenario_result")
}

################################################################################
# REPORT GENERATION
################################################################################

generate_json_report() {
    local end_time
    local duration
    local results_json
    
    end_time=$(get_iso_timestamp)
    
    # Count actual requests from evidence files (fixes the counter bug)
    TOTAL_REQUESTS=$(find "$EVIDENCE_DIR" -name "*_request.txt" 2>/dev/null | wc -l | tr -d ' ')
    
    # Calculate duration (simple approach)
    duration="N/A"
    
    # Build results array
    results_json="["
    for ((i=0; i<${#SCENARIO_RESULTS[@]}; i++)); do
        results_json+="${SCENARIO_RESULTS[$i]}"
        if [[ $i -lt $((${#SCENARIO_RESULTS[@]} - 1)) ]]; then
            results_json+=","
        fi
    done
    results_json+="]"
    
    # Generate final JSON report
    jq -n \
        --arg framework "$UASF_NAME" \
        --arg version "$UASF_VERSION" \
        --arg target "$TARGET_URL" \
        --arg timestamp "$end_time" \
        --argjson total "$TOTAL_SCENARIOS" \
        --argjson requests "$TOTAL_REQUESTS" \
        --argjson results "$results_json" \
        '{
            framework: $framework,
            version: $version,
            target: $target,
            timestamp: $timestamp,
            total_scenarios: $total,
            total_requests: $requests,
            results: $results
        }' > "$JSON_OUTPUT"
    
    log SUCCESS "JSON report saved: $JSON_OUTPUT"
    audit_log "REPORT_GENERATED: JSON -> $JSON_OUTPUT ($TOTAL_REQUESTS requests)"
}

generate_markdown_summary() {
    local summary_file="${OUTPUT_DIR}/summary.md"
    local timestamp
    timestamp=$(get_iso_timestamp)
    
    # Ensure we have the latest request count
    TOTAL_REQUESTS=$(find "$EVIDENCE_DIR" -name "*_request.txt" 2>/dev/null | wc -l | tr -d ' ')
    
    {
        echo "# UASF Attack Simulation Summary"
        echo ""
        echo "**Framework**: ${UASF_NAME} v${UASF_VERSION}"
        echo "**Target**: ${TARGET_URL}"
        echo "**Timestamp**: ${timestamp}"
        echo "**Total Scenarios**: ${TOTAL_SCENARIOS}"
        echo "**Total Requests**: ${TOTAL_REQUESTS}"
        echo ""
        echo "---"
        echo ""
        echo "## Executive Summary"
        echo ""
        
        # Calculate overall statistics
        local total_allowed=0
        local total_blocked=0
        local total_challenged=0
        local total_inconclusive=0
        
        for result in "${SCENARIO_RESULTS[@]}"; do
            local status
            status=$(echo "$result" | jq -r '.status')
            case "$status" in
                "$RESULT_ALLOWED") ((total_allowed++)) ;;
                "$RESULT_BLOCKED") ((total_blocked++)) ;;
                "$RESULT_CHALLENGED") ((total_challenged++)) ;;
                "$RESULT_INCONCLUSIVE") ((total_inconclusive++)) ;;
            esac
        done
        
        echo "- **ALLOWED**: $total_allowed scenarios"
        echo "- **BLOCKED**: $total_blocked scenarios"
        echo "- **CHALLENGED**: $total_challenged scenarios"
        echo "- **INCONCLUSIVE**: $total_inconclusive scenarios"
        echo ""
        
        # Calculate effectiveness
        if [[ $TOTAL_SCENARIOS -gt 0 ]]; then
            local effectiveness
            effectiveness=$(awk "BEGIN {printf \"%.1f\", ($total_blocked + $total_challenged) * 100.0 / $TOTAL_SCENARIOS}")
            echo "**Security Control Effectiveness**: ${effectiveness}%"
            echo ""
        fi
        
        echo "---"
        echo ""
        echo "## Scenario Results"
        echo ""
        
        # Detail each scenario
        for result in "${SCENARIO_RESULTS[@]}"; do
            local name desc status steps allowed blocked challenged inconclusive
            name=$(echo "$result" | jq -r '.scenario')
            desc=$(echo "$result" | jq -r '.description')
            status=$(echo "$result" | jq -r '.status')
            steps=$(echo "$result" | jq -r '.steps_executed')
            allowed=$(echo "$result" | jq -r '.results.allowed')
            blocked=$(echo "$result" | jq -r '.results.blocked')
            challenged=$(echo "$result" | jq -r '.results.challenged')
            inconclusive=$(echo "$result" | jq -r '.results.inconclusive')
            
            echo "### ${name}"
            echo ""
            echo "**Description**: ${desc}"
            echo ""
            echo "**Final Status**: \`${status}\`"
            echo ""
            echo "**Steps Executed**: ${steps}"
            echo ""
            echo "**Breakdown**:"
            echo "- Allowed: ${allowed}"
            echo "- Blocked: ${blocked}"
            echo "- Challenged: ${challenged}"
            echo "- Inconclusive: ${inconclusive}"
            echo ""
            echo "---"
            echo ""
        done
        
        echo "## Evidence Files"
        echo ""
        echo "All request/response evidence stored in: \`${EVIDENCE_DIR}\`"
        echo ""
        echo "Total evidence files: $(find "$EVIDENCE_DIR" -type f | wc -l)"
        echo ""
        echo "---"
        echo ""
        echo "## Methodology"
        echo ""
        echo "This assessment used the UASF (Universal Attack Simulation Framework) to execute"
        echo "controlled, safe attack scenarios against the target application. Each scenario"
        echo "simulates a realistic Red Team attack chain to validate security controls."
        echo ""
        echo "**Classification**:"
        echo "- **BLOCKED**: Attack detected and prevented by WAF/WAAP"
        echo "- **ALLOWED**: Attack reached application without intervention"
        echo "- **CHALLENGED**: Rate limiting or CAPTCHA presented"
        echo "- **INCONCLUSIVE**: Unexpected response or timeout"
        echo ""
        echo "**Scope**: All requests enforced within regex: \`${SCOPE_REGEX}\`"
        echo ""
        echo "**Rate Limit**: ${RPS} requests/second"
        echo ""
        echo "---"
        echo ""
        echo "*Generated by ${UASF_NAME} v${UASF_VERSION}*"
        
    } > "$summary_file"
    
    log SUCCESS "Markdown summary saved: $summary_file"
    audit_log "REPORT_GENERATED: Markdown -> $summary_file"
}

################################################################################
# MAIN EXECUTION FLOW
################################################################################

main() {
    log INFO "Starting ${UASF_NAME} v${UASF_VERSION}"
    
    # Check dependencies
    check_dependencies
    
    # Parse and validate arguments
    parse_args "$@"
    
    # Set up cleanup handler for interrupts
    trap cleanup_handler SIGINT SIGTERM
    
    # Display configuration
    log INFO "Target: $TARGET_URL"
    log INFO "Scenarios: $SCENARIO_DIR"
    log INFO "Output: $OUTPUT_DIR"
    log INFO "Evidence: $EVIDENCE_DIR"
    log INFO "Scope Regex: $SCOPE_REGEX"
    log INFO "RPS Limit: $RPS"
    log INFO "Timeout: ${TIMEOUT}s"
    
    # Record start time
    START_TIME=$(get_iso_timestamp)
    audit_log "EXECUTION_STARTED"
    
    # Find all scenario files
    local scenario_files=()
    while IFS= read -r -d '' file; do
        scenario_files+=("$file")
    done < <(find "$SCENARIO_DIR" -name "*.json" -type f -print0 | sort -z)
    
    TOTAL_SCENARIOS=${#scenario_files[@]}
    
    if [[ $TOTAL_SCENARIOS -eq 0 ]]; then
        die "No scenario files found in: $SCENARIO_DIR"
    fi
    
    log INFO "Found $TOTAL_SCENARIOS scenario(s)"
    audit_log "SCENARIOS_FOUND: $TOTAL_SCENARIOS"
    
    # Execute each scenario
    for scenario_file in "${scenario_files[@]}"; do
        execute_scenario "$scenario_file" || log WARN "Scenario execution failed: $scenario_file"
    done
    
    # Generate reports
    log INFO "Generating reports..."
    audit_log "GENERATING_REPORTS"
    generate_json_report
    generate_markdown_summary
    
    # Final summary
    log SUCCESS "Execution complete!"
    log INFO "Total scenarios: $TOTAL_SCENARIOS"
    log INFO "Total requests: $TOTAL_REQUESTS"
    log INFO "Results: $JSON_OUTPUT"
    log INFO "Summary: ${OUTPUT_DIR}/summary.md"
    log INFO "Evidence: $EVIDENCE_DIR"
    
    # Final audit entry
    audit_log "EXECUTION_COMPLETE: $TOTAL_SCENARIOS scenarios, $TOTAL_REQUESTS requests"
}

################################################################################
# ENTRY POINT
################################################################################

# Run main function with all arguments
main "$@"
