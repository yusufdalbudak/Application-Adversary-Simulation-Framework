#!/usr/bin/env bash
################################################################################
# UASF Quick Start Script
# Simplified wrapper for easy usage
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# Default values
DEFAULT_SCENARIOS="./scenarios"
DEFAULT_RPS=2

# Print usage
usage() {
    cat <<EOF
${GREEN}UASF Quick Start${RESET} - Simplified attack simulation tool

${YELLOW}EASY USAGE:${RESET}
    $0 <target-url>

${YELLOW}EXAMPLES:${RESET}
    $0 https://example.com
    $0 https://api.example.com
    $0 https://cybersecdev.com

${YELLOW}ADVANCED OPTIONS:${RESET}
    $0 <target-url> [--rps <number>] [--scenarios <directory>]

${YELLOW}WHAT IT DOES:${RESET}
    - Automatically creates output directories
    - Uses sensible defaults
    - Generates timestamped reports
    - Runs all scenarios in ./scenarios directory

${YELLOW}OUTPUT LOCATION:${RESET}
    - Reports: ./runs/<timestamp>/
    - Evidence: ./runs/<timestamp>/evidence/
    - Results: ./runs/<timestamp>/results.json

EOF
}

# Show help
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    usage
    exit 0
fi

# Parse target URL
TARGET_URL="$1"
shift

# Parse optional arguments
SCENARIOS="$DEFAULT_SCENARIOS"
RPS="$DEFAULT_RPS"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rps)
            RPS="$2"
            shift 2
            ;;
        --scenarios)
            SCENARIOS="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            usage
            exit 1
            ;;
    esac
done

# Validate target URL
if [[ ! "$TARGET_URL" =~ ^https?:// ]]; then
    echo -e "${RED}Error: Invalid URL. Must start with http:// or https://${RESET}"
    echo "Example: $0 https://example.com"
    exit 1
fi

# Extract domain for scope regex
DOMAIN=$(echo "$TARGET_URL" | sed -E 's|^(https?://[^/]+).*|\1|')
SCOPE_REGEX="^$(echo "$DOMAIN" | sed 's/\./\\./g')"

# Create timestamped run directory
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RUN_DIR="./runs/${TIMESTAMP}"
OUTPUT_DIR="${RUN_DIR}/output"
EVIDENCE_DIR="${RUN_DIR}/evidence"
JSON_OUTPUT="${RUN_DIR}/results.json"

# Create directories
mkdir -p "$RUN_DIR"

# Display what we're doing
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}UASF Quick Scan${RESET}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BLUE}Target:${RESET}      $TARGET_URL"
echo -e "${BLUE}Scenarios:${RESET}   $SCENARIOS"
echo -e "${BLUE}RPS Limit:${RESET}   $RPS requests/second"
echo -e "${BLUE}Output:${RESET}      $RUN_DIR"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# Check if scenarios directory exists
if [[ ! -d "$SCENARIOS" ]]; then
    echo -e "${RED}Error: Scenarios directory not found: $SCENARIOS${RESET}"
    exit 1
fi

# Count scenarios
SCENARIO_COUNT=$(find "$SCENARIOS" -name "*.json" -type f | wc -l | tr -d ' ')
if [[ "$SCENARIO_COUNT" -eq 0 ]]; then
    echo -e "${RED}Error: No scenario files found in: $SCENARIOS${RESET}"
    exit 1
fi

echo -e "${YELLOW}Found $SCENARIO_COUNT scenario(s)${RESET}"
echo ""

# Run UASF
echo -e "${BLUE}Starting scan...${RESET}"
echo ""

./uasf.sh run \
    --target "$TARGET_URL" \
    --scenarios "$SCENARIOS" \
    --out "$OUTPUT_DIR" \
    --evidence "$EVIDENCE_DIR" \
    --json "$JSON_OUTPUT" \
    --scope-regex "$SCOPE_REGEX" \
    --rps "$RPS"

EXIT_CODE=$?

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}✓ Scan completed successfully!${RESET}"
    echo ""
    echo -e "${YELLOW}Results:${RESET}"
    echo -e "  📊 Summary:  ${OUTPUT_DIR}/summary.md"
    echo -e "  📄 JSON:     ${JSON_OUTPUT}"
    echo -e "  📁 Evidence: ${EVIDENCE_DIR}"
    echo -e "  📝 Audit:    ${OUTPUT_DIR}/audit.log"
    echo ""
    
    # Show quick stats
    if [[ -f "$JSON_OUTPUT" ]]; then
        TOTAL_REQUESTS=$(jq -r '.total_requests // 0' "$JSON_OUTPUT" 2>/dev/null || echo "0")
        echo -e "${BLUE}Quick Stats:${RESET}"
        echo -e "  Total requests: $TOTAL_REQUESTS"
        
        # Show scenario results
        echo ""
        echo -e "${YELLOW}Scenario Results:${RESET}"
        jq -r '.results[] | "  \(.status | if . == "BLOCKED" then "🛡️" elif . == "ALLOWED" then "⚠️" elif . == "CHALLENGED" then "🔒" else "❓" end) \(.scenario): \(.status)"' "$JSON_OUTPUT" 2>/dev/null || true
    fi
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BLUE}💡 Tip:${RESET} View the summary with: cat ${OUTPUT_DIR}/summary.md"
else
    echo -e "${RED}✗ Scan failed with exit code: $EXIT_CODE${RESET}"
fi

echo ""
exit $EXIT_CODE
