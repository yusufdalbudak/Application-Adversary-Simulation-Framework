# UASF Usage Examples

This document provides practical examples for using the Universal Attack Simulation Framework.

## Table of Contents

1. [Basic Examples](#basic-examples)
2. [Advanced Filtering](#advanced-filtering)
3. [Rate Limiting Scenarios](#rate-limiting-scenarios)
4. [Evidence Analysis](#evidence-analysis)
5. [Result Interpretation](#result-interpretation)
6. [Automation Examples](#automation-examples)

## Basic Examples

### Example 1: Testing Against httpbin.org

```bash
./uasf.sh run \
  --target https://httpbin.org \
  --scenarios ./scenarios \
  --out ./output \
  --evidence ./evidence \
  --json ./results.json \
  --scope-regex "^https://httpbin\.org"
```

**Expected Output:**
- Most scenarios will return ALLOWED (httpbin has no WAF)
- Evidence files in `./evidence/`
- Summary in `./output/summary.md`
- JSON results in `./results.json`

### Example 2: Testing a Protected Application

```bash
./uasf.sh run \
  --target https://protected.example.com \
  --scenarios ./scenarios \
  --out ./output-protected \
  --evidence ./evidence-protected \
  --json ./results-protected.json \
  --scope-regex "^https://protected\.example\.com" \
  --rps 3
```

**Expected Output:**
- SQL injection scenarios: BLOCKED
- XSS scenarios: BLOCKED
- IDOR scenarios: Mix of BLOCKED and ALLOWED
- Evidence of WAF responses

### Example 3: API-Specific Testing

```bash
./uasf.sh run \
  --target https://api.example.com \
  --scenarios ./scenarios \
  --out ./output-api \
  --evidence ./evidence-api \
  --json ./results-api.json \
  --scope-regex "^https://api\.example\.com" \
  --rps 2 \
  --timeout 60
```

**Use Case:** Testing API rate limiting and authentication controls

## Advanced Filtering

### Example 4: Testing Only SQL Injection Scenarios

```bash
# Create a filtered scenario directory
mkdir -p scenarios-sqli
cp scenarios/sqli-*.json scenarios-sqli/

# Run UASF with filtered scenarios
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios-sqli \
  --out ./output-sqli \
  --evidence ./evidence-sqli \
  --json ./results-sqli.json \
  --scope-regex "^https://example\.com"
```

### Example 5: Testing Only Authentication Scenarios

```bash
mkdir -p scenarios-auth
cp scenarios/auth-*.json scenarios-auth/

./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios-auth \
  --out ./output-auth \
  --evidence ./evidence-auth \
  --json ./results-auth.json \
  --scope-regex "^https://example\.com" \
  --rps 1
```

**Rationale:** Lower RPS for authentication testing to avoid account lockouts

## Rate Limiting Scenarios

### Example 6: High-Volume Testing

```bash
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios/bot-simulation.json \
  --out ./output-highvol \
  --evidence ./evidence-highvol \
  --json ./results-highvol.json \
  --scope-regex "^https://example\.com" \
  --rps 10
```

**Purpose:** Test anti-automation and bot detection controls

### Example 7: Low-Rate Testing

```bash
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios \
  --out ./output-lowrate \
  --evidence ./evidence-lowrate \
  --json ./results-lowrate.json \
  --scope-regex "^https://example\.com" \
  --rps 1
```

**Purpose:** Avoid triggering rate limits while testing detection controls

## Evidence Analysis

### Example 8: Analyzing Evidence Files

```bash
# Count total requests made
total_requests=$(ls -1 evidence/*_request.txt 2>/dev/null | wc -l)
echo "Total requests: $total_requests"

# Find all blocked requests (HTTP 403)
echo "Blocked requests:"
grep -l "Status Code: 403" evidence/*_response.txt

# Find all rate-limited requests (HTTP 429)
echo "Rate-limited requests:"
grep -l "Status Code: 429" evidence/*_response.txt

# Extract all unique status codes
echo "All status codes encountered:"
grep "Status Code:" evidence/*_response.txt | \
  awk '{print $3}' | sort -n | uniq -c | sort -rn
```

### Example 9: Finding WAF Signatures in Responses

```bash
# Search for common WAF signatures
grep -i "blocked\|firewall\|security\|waf" evidence/*_response.txt

# Check for CAPTCHA challenges
grep -i "captcha\|challenge" evidence/*_response.txt

# Look for CloudFlare protection
grep -i "cloudflare\|cf-ray" evidence/*_response.txt
```

### Example 10: Extracting Failed Scenarios

```bash
# Parse JSON results for ALLOWED scenarios (potential vulnerabilities)
jq '.results[] | select(.status == "ALLOWED") | {scenario, description, status}' \
  results.json
```

## Result Interpretation

### Example 11: Calculating Control Effectiveness

```bash
# Extract statistics from JSON
total_scenarios=$(jq '.total_scenarios' results.json)
blocked=$(jq '[.results[] | select(.status == "BLOCKED")] | length' results.json)
challenged=$(jq '[.results[] | select(.status == "CHALLENGED")] | length' results.json)
allowed=$(jq '[.results[] | select(.status == "ALLOWED")] | length' results.json)

# Calculate effectiveness
effectiveness=$(awk "BEGIN {printf \"%.1f\", ($blocked + $challenged) * 100.0 / $total_scenarios}")

echo "=== Security Control Effectiveness ==="
echo "Total Scenarios: $total_scenarios"
echo "Blocked: $blocked"
echo "Challenged: $challenged"
echo "Allowed: $allowed"
echo "Effectiveness: ${effectiveness}%"
```

**Output Example:**
```
=== Security Control Effectiveness ===
Total Scenarios: 5
Blocked: 3
Challenged: 1
Allowed: 1
Effectiveness: 80.0%
```

### Example 12: Comparing Before/After WAF Tuning

```bash
# Run test before tuning
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios \
  --out ./output-before \
  --evidence ./evidence-before \
  --json ./results-before.json \
  --scope-regex "^https://example\.com"

# Make WAF configuration changes...

# Run test after tuning
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios \
  --out ./output-after \
  --evidence ./evidence-after \
  --json ./results-after.json \
  --scope-regex "^https://example\.com"

# Compare results
echo "Before tuning:"
jq '.results[] | {scenario, status}' results-before.json

echo "After tuning:"
jq '.results[] | {scenario, status}' results-after.json
```

## Automation Examples

### Example 13: Scheduled Security Validation

```bash
#!/bin/bash
# scheduled-validation.sh

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET="https://production.example.com"
OUTPUT_BASE="./validation-runs/${TIMESTAMP}"

mkdir -p "$OUTPUT_BASE"

./uasf.sh run \
  --target "$TARGET" \
  --scenarios ./scenarios \
  --out "${OUTPUT_BASE}/output" \
  --evidence "${OUTPUT_BASE}/evidence" \
  --json "${OUTPUT_BASE}/results.json" \
  --scope-regex "^${TARGET}" \
  --rps 3

# Send notification if any scenarios were ALLOWED
allowed_count=$(jq '[.results[] | select(.status == "ALLOWED")] | length' \
  "${OUTPUT_BASE}/results.json")

if [[ $allowed_count -gt 0 ]]; then
  echo "WARNING: $allowed_count scenario(s) were ALLOWED!" | \
    mail -s "UASF Alert: Potential Vulnerabilities Detected" security@example.com
fi
```

### Example 14: Multi-Environment Testing

```bash
#!/bin/bash
# multi-env-test.sh

ENVIRONMENTS=(
  "dev:https://dev.example.com"
  "staging:https://staging.example.com"
  "production:https://production.example.com"
)

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

for env_pair in "${ENVIRONMENTS[@]}"; do
  IFS=':' read -r env_name target <<< "$env_pair"
  
  echo "Testing $env_name environment..."
  
  ./uasf.sh run \
    --target "$target" \
    --scenarios ./scenarios \
    --out "./results/${TIMESTAMP}/${env_name}/output" \
    --evidence "./results/${TIMESTAMP}/${env_name}/evidence" \
    --json "./results/${TIMESTAMP}/${env_name}/results.json" \
    --scope-regex "^${target}" \
    --rps 2
  
  # Generate effectiveness report
  effectiveness=$(jq '[.results[] | select(.status == "BLOCKED" or .status == "CHALLENGED")] | length' \
    "./results/${TIMESTAMP}/${env_name}/results.json")
  total=$(jq '.total_scenarios' "./results/${TIMESTAMP}/${env_name}/results.json")
  
  echo "$env_name: $effectiveness/$total scenarios blocked/challenged"
done
```

### Example 15: CI/CD Integration

```bash
#!/bin/bash
# ci-security-gate.sh
# Usage: Run as part of CI/CD pipeline before production deployment

set -e

STAGING_URL="https://staging.example.com"
MIN_EFFECTIVENESS=80  # Minimum 80% block rate required

echo "Running UASF security validation..."

./uasf.sh run \
  --target "$STAGING_URL" \
  --scenarios ./scenarios \
  --out ./ci-output \
  --evidence ./ci-evidence \
  --json ./ci-results.json \
  --scope-regex "^${STAGING_URL}" \
  --rps 5

# Calculate effectiveness
total=$(jq '.total_scenarios' ci-results.json)
blocked_challenged=$(jq '[.results[] | select(.status == "BLOCKED" or .status == "CHALLENGED")] | length' ci-results.json)
effectiveness=$(awk "BEGIN {printf \"%.0f\", $blocked_challenged * 100.0 / $total}")

echo "Security control effectiveness: ${effectiveness}%"

if [[ $effectiveness -lt $MIN_EFFECTIVENESS ]]; then
  echo "FAIL: Security controls below threshold (${effectiveness}% < ${MIN_EFFECTIVENESS}%)"
  exit 1
else
  echo "PASS: Security controls meet threshold (${effectiveness}% >= ${MIN_EFFECTIVENESS}%)"
  exit 0
fi
```

### Example 16: Regression Testing After Updates

```bash
#!/bin/bash
# regression-test.sh

BASELINE="./baseline-results.json"
CURRENT="./current-results.json"

# Run current test
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios \
  --out ./output-regression \
  --evidence ./evidence-regression \
  --json "$CURRENT" \
  --scope-regex "^https://example\.com"

# Compare with baseline
echo "=== Regression Analysis ==="

# Get scenario statuses from baseline
baseline_blocked=$(jq '[.results[] | select(.status == "BLOCKED")] | length' "$BASELINE")
current_blocked=$(jq '[.results[] | select(.status == "BLOCKED")] | length' "$CURRENT")

echo "Baseline blocked scenarios: $baseline_blocked"
echo "Current blocked scenarios: $current_blocked"

# Check for regressions (previously blocked, now allowed)
jq -r --slurpfile baseline "$BASELINE" '
  .results[] as $current |
  $baseline[0].results[] |
  select(.scenario == $current.scenario and .status == "BLOCKED" and $current.status == "ALLOWED") |
  "REGRESSION: \(.scenario) was BLOCKED, now ALLOWED"
' "$CURRENT"
```

## Custom Scenario Examples

### Example 17: Creating a Path Traversal Test

```bash
cat > scenarios/path-traversal.json <<'EOF'
{
  "name": "Path Traversal Detection",
  "description": "Test for directory traversal vulnerability detection",
  "steps": [
    {
      "method": "GET",
      "path": "/files?file=../../../../etc/passwd",
      "headers": {
        "User-Agent": "UASF/1.0 (Security Testing)"
      },
      "expect_http_codes": [200, 403, 404]
    },
    {
      "method": "GET",
      "path": "/download?path=..%2F..%2F..%2Fetc%2Fpasswd",
      "headers": {
        "User-Agent": "UASF/1.0 (Security Testing)"
      },
      "expect_http_codes": [200, 403, 404]
    }
  ]
}
EOF
```

### Example 18: Creating a Custom Header Injection Test

```bash
cat > scenarios/header-injection.json <<'EOF'
{
  "name": "Header Injection Detection",
  "description": "Test for HTTP header injection vulnerability detection",
  "steps": [
    {
      "method": "GET",
      "path": "/redirect?url=https://example.com",
      "headers": {
        "User-Agent": "UASF/1.0 (Security Testing)",
        "X-Custom-Header": "value\r\nX-Injected: malicious"
      },
      "expect_http_codes": [200, 400, 403]
    }
  ]
}
EOF
```

## Tips and Best Practices

### Tip 1: Always Start with Low RPS

```bash
# Start conservative
./uasf.sh run --target https://example.com --scenarios ./scenarios \
  --out ./output --evidence ./evidence --json ./results.json \
  --scope-regex "^https://example\.com" --rps 1

# Increase gradually if needed
```

### Tip 2: Use Descriptive Output Directories

```bash
# Include timestamp and target in output path
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
TARGET_NAME="production"

./uasf.sh run \
  --target https://production.example.com \
  --scenarios ./scenarios \
  --out "./results/${TIMESTAMP}_${TARGET_NAME}/output" \
  --evidence "./results/${TIMESTAMP}_${TARGET_NAME}/evidence" \
  --json "./results/${TIMESTAMP}_${TARGET_NAME}/results.json" \
  --scope-regex "^https://production\.example\.com"
```

### Tip 3: Archive Evidence for Compliance

```bash
# After running UASF, create an archive
tar -czf "evidence_$(date +%Y%m%d).tar.gz" evidence/

# Store securely for audit purposes
mv "evidence_$(date +%Y%m%d).tar.gz" /secure/audit/archive/
```

---

**For more information, see the main [README.md](README.md).**
