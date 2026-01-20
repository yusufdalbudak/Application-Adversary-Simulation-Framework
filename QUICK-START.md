# UASF Quick Start Guide

## 🚀 Super Easy Usage

Instead of the long command, now you can simply:

```bash
./uasf-quick.sh https://example.com
```

That's it! ✨

## 📋 What It Does Automatically

- ✅ Creates organized output directories with timestamps
- ✅ Auto-generates scope regex from URL
- ✅ Uses sensible default settings
- ✅ Shows colorful progress and results
- ✅ Displays quick statistics at the end

## 🎯 Examples

### Scan any website
```bash
./uasf-quick.sh https://cybersecdev.com
```

### Scan with custom rate limit
```bash
./uasf-quick.sh https://example.com --rps 5
```

### Use custom scenarios
```bash
./uasf-quick.sh https://api.example.com --scenarios ./my-scenarios
```

## 📁 Output Structure

All results go into organized directories:
```
runs/
└── 20260120_142500/          # Timestamped
    ├── results.json          # JSON output
    ├── output/
    │   ├── summary.md        # Human-readable summary
    │   └── audit.log         # Compliance trail
    └── evidence/             # All request/response pairs
```

## 🆚 Comparison

### Before (Original Command)
```bash
./uasf.sh run \
  --target https://example.com \
  --scenarios ./scenarios \
  --out ./output \
  --evidence ./evidence \
  --json ./results.json \
  --scope-regex "^https://example\.com" \
  --rps 2
```

### After (Quick Command)
```bash
./uasf-quick.sh https://example.com
```

**96% less typing!** 🎉

## 🔧 Advanced Options

| Option | Description | Example |
|--------|-------------|---------|
| `--rps <number>` | Set requests per second | `--rps 5` |
| `--scenarios <dir>` | Custom scenarios directory | `--scenarios ./custom` |

## 💡 Pro Tips

**View results quickly:**
```bash
# After scan completes, view summary
cat runs/20260120_*/output/summary.md

# View audit log
cat runs/20260120_*/output/audit.log
```

**Keep runs organized:**
```bash
# List all scan runs
ls -lt runs/

# Remove old runs
rm -rf runs/20260119_*
```

## 🎨 Visual Output

The quick script shows:
- 🛡️ BLOCKED scenarios
- ⚠️ ALLOWED scenarios  
- 🔒 CHALLENGED scenarios
- ❓ INCONCLUSIVE scenarios

## Need the Full Command?

For advanced use cases, the original `uasf.sh` is still available with all options.

Use `./uasf-quick.sh --help` to see all options!
