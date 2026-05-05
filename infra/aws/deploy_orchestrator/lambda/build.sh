#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
rm -rf package
mkdir -p package
python3 -m pip install -q -r requirements.txt -t package/
cp handler.py package/
