#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

python3 -m py_compile shrink_empty_codes.py

python3 shrink_empty_codes.py \
  --main \
  --report shrink_empty_codes_report_remaining.txt

echo
echo "Report written to: shrink_empty_codes_report_remaining.txt"
echo "If safe_candidates is not 0, run:"
echo
echo "  python3 shrink_empty_codes.py --main --report shrink_empty_codes_report_remaining.txt --apply --repeat"

