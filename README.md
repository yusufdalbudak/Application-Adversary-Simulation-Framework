# AASF – Application Aversary Simulation Framework

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/yourusername/uasf)
[![License](https://img.shields.io/badge/license-Authorized%20Testing%20Only-red.svg)](LICENSE)

A production-grade Red Team attack simulation framework designed for validating Web Application and API Protection (WAAP) and Web Application Firewall (WAF) security controls.

## ⚠️ Legal Warning

**THIS TOOL IS FOR AUTHORIZED SECURITY TESTING ONLY.**

- Unauthorized use is **illegal** and **unethical**
- Always obtain **explicit written permission** before testing
- This framework assumes **authorized access** to target systems
- Misuse may result in criminal prosecution

## 🎯 Purpose

UASF enables security teams to:

- **Validate security controls** through realistic attack simulations
- **Reduce false positives** by testing detection accuracy
- **Prove exploitability** with evidence-based reporting
- **Measure control effectiveness** with quantitative metrics
- **Support continuous validation** of WAAP/WAF configurations

## 🏗️ Architecture

### Design Philosophy

- **Red Team mindset, Blue Team responsibility**
- **Evidence-first approach** (all requests/responses captured)
- **Safe and non-destructive** (detection testing, not exploitation)
- **Deterministic execution** (same input → same output)
- **Production-ready** (no placeholders, no pseudo-code)

### Key Features

✅ **Scenario-driven execution** - JSON-based attack chains  
✅ **Strict scope enforcement** - Regex-based URL validation  
✅ **Rate limiting** - Configurable requests per second  
✅ **Full evidence collection** - Request/response pairs with timestamps  
✅ **Result classification** - BLOCKED/ALLOWED/CHALLENGED/INCONCLUSIVE  
✅ **Dual output formats** - JSON for automation, Markdown for humans  
✅ **Zero dependencies** - Only standard Linux tools required  
✅ **Cross-platform** - Works on Linux and macOS  

## 📋 Requirements

### System Requirements

- Linux (tested on Kali Linux) or macOS
- Bash 4.0+ (POSIX compatible)

### Dependencies

All standard tools (should be pre-installed):

- `curl` - HTTP client
- `jq` - JSON processor
- `sed`, `awk`, `grep` - Text processing
- `date` - Timestamp generation

**No Python, no Go, no Node.js required.**

## 🚀 Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/Red-Team-Custom-Framework.git
cd Red-Team-Custom-Framework

# Make the script executable
chmod +x uasf.sh

# Verify installation
./uasf.sh --help
```

## 📖 Usage

### Basic Syntax

```bash
./uasf.sh run \
  --target <base_url> \
  --scenarios <scenario_directory> \
  --out <output_directory> \
  --evidence <evidence_directory> \
  --json <results.json> \
  --scope-regex <regex> \
  [--rps <rate_limit>] \
  [--concurrency <workers>] \
  [--timeout <seconds>]
```

### Required Arguments

| Argument | Description | Example |
|----------|-------------|---------|
| `--target` | Target base URL | `https://example.com` |
| `--scenarios` | Directory containing scenario JSON files | `./scenarios` |
| `--out` | Output directory for reports | `./output` |
| `--evidence` | Directory for evidence files | `./evidence` |
| `--json` | JSON results output file | `./results.json` |
| `--scope-regex` | Regex to enforce request scope | `^https://example\.com` |

### Optional Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `--rps` | `5` | Requests per second limit |
| `--concurrency` | `1` | Concurrent workers (future use) |
| `--timeout` | `30` | HTTP timeout in seconds |

### Example Commands

#### Basic Execution

```bash
./uasf.sh run \
  --target https://httpbin.org \
  --scenarios ./scenarios \
  --out ./output \
  --evidence ./evidence \
  --json ./results.json \
  --scope-regex "^https://httpbin\.org"
```

#### With Custom Rate Limiting

```bash
./uasf.sh run \
  --target https://api.example.com \
  --scenarios ./scenarios \
  --out ./output \
  --evidence ./evidence \
  --json ./results.json \
  --scope-regex "^https://api\.example\.com" \
  --rps 2 \
  --timeout 60
```

## 📝 Scenario Development

### Scenario Schema

Scenarios are JSON files with the following structure:

```json
{
  "name": "Scenario Name",
  "description": "Detailed description of the attack chain",
  "steps": [
    {
      "method": "GET",
      "path": "/api/endpoint",
      "headers": {
        "User-Agent": "UASF/1.0",
        "Authorization": "Bearer token"
      },
      "body": "",
      "repeat": 1,
      "sleep_ms": 0,
      "expect_http_codes": [200, 403, 429]
    }
  ]
}
```

### Step Parameters

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `method` | string | Yes | HTTP method (GET, POST, PUT, DELETE) |
| `path` | string | Yes | URL path (appended to target) |
| `headers` | object | No | Custom HTTP headers |
| `body` | string | No | Request body (for POST/PUT) |
| `repeat` | number | No | Number of times to repeat this step (default: 1) |
| `sleep_ms` | number | No | Milliseconds to sleep after step (default: 0) |
| `expect_http_codes` | array | No | Expected HTTP status codes |

### Included Scenarios

The framework includes five production-ready scenarios:

1. **`sqli-smoke.json`** - SQL Injection detection testing
2. **`xss-smoke.json`** - Reflected XSS detection testing
3. **`idor-validation.json`** - Broken access control testing
4. **`auth-abuse.json`** - Authentication flow abuse testing
5. **`bot-simulation.json`** - Bot detection and rate limiting testing

### Creating Custom Scenarios

```bash
# Create a new scenario file
cat > scenarios/custom-test.json <<'EOF'
{
  "name": "Custom Test",
  "description": "Custom attack simulation",
  "steps": [
    {
      "method": "GET",
      "path": "/vulnerable-endpoint?param=<payload>",
      "headers": {
        "User-Agent": "UASF/1.0 (Security Testing)"
      },
      "expect_http_codes": [200, 403]
    }
  ]
}
EOF
```

## 📊 Output Interpretation

### Result Classifications

| Status | Meaning | Indicators |
|--------|---------|------------|
| **BLOCKED** | Attack detected and prevented | HTTP 403, 406, WAF signature in response |
| **ALLOWED** | Attack reached application | HTTP 200-299 without WAF intervention |
| **CHALLENGED** | Rate limiting or CAPTCHA presented | HTTP 429, 503, CAPTCHA detected |
| **INCONCLUSIVE** | Unexpected response | Timeout, unexpected status code |

### JSON Output

```json
{
  "framework": "UASF",
  "version": "1.0.0",
  "target": "https://example.com",
  "timestamp": "2026-01-19T20:11:18Z",
  "total_scenarios": 5,
  "total_requests": 37,
  "results": [
    {
      "scenario": "SQL Injection Smoke Test",
      "description": "Safe SQL injection detection test...",
      "status": "BLOCKED",
      "steps_executed": 5,
      "results": {
        "allowed": 0,
        "blocked": 5,
        "challenged": 0,
        "inconclusive": 0
      }
    }
  ]
}
```

### Markdown Summary

Generated at `${OUTPUT_DIR}/summary.md`:

- Executive summary with statistics
- Scenario-by-scenario breakdown
- Security control effectiveness percentage
- Evidence file references
- Methodology documentation

### Evidence Files

All request/response pairs stored in `${EVIDENCE_DIR}`:

```
evidence/
├── 20260119_201130_request.txt
├── 20260119_201130_response.txt
├── 20260119_201131_request.txt
└── 20260119_201131_response.txt
```

Each evidence file contains:
- Full HTTP request (method, URL, headers, body)
- Full HTTP response (status, headers, body)
- ISO 8601 timestamps

## 🛡️ How This Validates WAAP/WAF Platforms

### Detection Effectiveness

- Framework sends known attack patterns
- WAF/WAAP should detect and block malicious requests
- Evidence shows which attacks were blocked vs. allowed
- Quantifies detection rate

### False Positive Reduction

- Mix legitimate and attack requests
- Helps tune WAF rules to reduce false positives
- Provides baseline for normal vs. attack traffic
- Validates signature accuracy

### Proof of Exploitability

- Evidence files prove which attacks succeeded
- Demonstrates real-world attack chains
- Shows gaps in protection layers
- Supports security posture reporting

### Control Validation

- Tests multiple attack vectors systematically
- Validates layered security (WAF + app controls)
- Provides repeatable validation process
- Enables continuous security validation

### Reporting for Stakeholders

- **Executive Summary**: Security control effectiveness percentage
- **Technical Evidence**: Full request/response pairs
- **Metrics**: Attack success/failure rates
- **Continuous Improvement**: Track changes over time

## 🔒 Safety Guarantees

### Attack Simulation Constraints

✅ **Non-destructive payloads** - Detection testing only  
✅ **No data extraction** - No actual SQLi enumeration  
✅ **No persistence** - No stored XSS or state changes  
✅ **No RCE attempts** - No shell commands  
✅ **Rate-limited** - Configurable RPS to prevent DoS  
✅ **Scope-enforced** - Strict regex validation  

### Ethical Considerations

- All scenarios assume **explicit authorization**
- Framework designed for **DEFENSIVE** validation
- Evidence collection is **audit-friendly**
- No credential theft or session hijacking
- No server state modification

## 🔧 Advanced Usage

### Filtering Scenarios

```bash
# Run only SQL injection tests
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios \
  --out ./output \
  --evidence ./evidence \
  --json ./results.json \
  --scope-regex "^https://example\.com"

# Then filter scenario directory
mkdir -p scenarios-sqli
cp scenarios/sqli-*.json scenarios-sqli/
```

### Analyzing Evidence

```bash
# Count total requests
ls -1 evidence/*_request.txt | wc -l

# Find all blocked requests (HTTP 403)
grep -l "Status Code: 403" evidence/*_response.txt

# Extract all response codes
grep "Status Code:" evidence/*_response.txt | sort | uniq -c
```

### Automating Execution

```bash
#!/bin/bash
# automated-scan.sh

TARGETS=(
  "https://staging.example.com"
  "https://production.example.com"
)

for target in "${TARGETS[@]}"; do
  timestamp=$(date +%Y%m%d_%H%M%S)
  
  ./uasf.sh run \
    --target "$target" \
    --scenarios ./scenarios \
    --out "./output/${timestamp}" \
    --evidence "./evidence/${timestamp}" \
    --json "./results/${timestamp}.json" \
    --scope-regex "^${target}" \
    --rps 3
done
```

## 🐛 Troubleshooting

### Common Issues

**Issue**: "Missing required dependencies"  
**Solution**: Install missing tools (`curl`, `jq`, etc.)

**Issue**: "Scope validation FAILED"  
**Solution**: Check that `--scope-regex` matches your `--target` URL

**Issue**: "No scenario files found"  
**Solution**: Ensure scenario directory contains `.json` files

**Issue**: "Connection timeout"  
**Solution**: Increase `--timeout` value or check network connectivity

### Debug Mode

Add debug output to the script:

```bash
# Add at top of uasf.sh
set -x  # Enable debug mode
```

## 📚 Directory Structure

```
Red-Team-Custom-Framework/
├── uasf.sh                          # Main executable
├── scenarios/                       # Attack scenarios
│   ├── sqli-smoke.json
│   ├── xss-smoke.json
│   ├── idor-validation.json
│   ├── auth-abuse.json
│   └── bot-simulation.json
├── output/                          # Generated reports (created at runtime)
│   └── summary.md
├── evidence/                        # Request/response evidence (created at runtime)
│   └── *_request.txt
│   └── *_response.txt
├── results.json                     # JSON output (created at runtime)
├── README.md                        # This file
└── EXAMPLES.md                      # Usage examples
```

## 🤝 Contributing

This is a production framework for authorized security testing. Contributions that enhance safety, accuracy, or reporting are welcome.

### Guidelines

- Maintain POSIX compatibility
- No external dependencies
- All scenarios must be **safe** and **non-destructive**
- Include evidence in pull requests
- Update documentation

## 📄 License

**Authorized Testing Only**

This framework is designed for authorized security testing. Use requires explicit written permission from target system owners.

## 🙏 Acknowledgments

Designed for Red Team engineers conducting ethical, authorized security validation.

---

**UASF v1.0.0** - Universal Attack Simulation Framework  
*Red Team mindset. Blue Team responsibility.*
