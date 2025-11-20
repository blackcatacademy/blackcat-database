#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASELINE="$SCRIPT_DIR/sqlfluff-baseline.txt"
VENV_DIR="$SCRIPT_DIR/.sqlfluff-venv"
PYTHON_BIN="${PYTHON:-python3}"
SQLFLUFF_BIN="$VENV_DIR/bin/sqlfluff"

if [[ ! -x "$SQLFLUFF_BIN" ]]; then
  rm -rf "$VENV_DIR"
  mkdir -p "$VENV_DIR"
  # Try creating venv with ensurepip; fall back to get-pip if ensurepip is missing
  if ! "$PYTHON_BIN" -m venv "$VENV_DIR" >/dev/null 2>&1; then
    echo "python venv missing ensurepip — bootstrapping pip via get-pip.py"
    "$PYTHON_BIN" -m venv --without-pip "$VENV_DIR"
    curl -sS https://bootstrap.pypa.io/get-pip.py -o "$VENV_DIR/get-pip.py"
    "$VENV_DIR/bin/python" "$VENV_DIR/get-pip.py" >/dev/null
  fi
  "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
  "$VENV_DIR/bin/python" -m pip install sqlfluff==3.0.7 >/dev/null
fi

git fetch origin main || true
CHANGED=$(git diff --name-only --diff-filter=ACMRT origin/main...HEAD | grep -E '\.sql$' || true)
if [ -z "$CHANGED" ]; then
  echo "No changed .sql files."
  exit 0
fi
echo "Running sqlfluff on changed files..."
"$SQLFLUFF_BIN" lint $CHANGED -f json > sqlfluff.json || true
"$PYTHON_BIN" - << 'PY'
import json, sys
data=json.load(open('sqlfluff.json'))
cur=set()
for f in data:
  for v in f.get('violations',[]):
    cur.add(f"{f['filepath']}:{v.get('line_no')}:{v.get('code')}")
open('sqlfluff.cur.txt','w').write("\n".join(sorted(cur)))
PY
touch "$BASELINE"
grep -vxF -f "$BASELINE" sqlfluff.cur.txt > sqlfluff.new.txt || true
NEW=$(wc -l < sqlfluff.new.txt | tr -d ' ')
if [ "$NEW" -gt 0 ]; then
  echo "::error ::SQL lint found $NEW new violations (not in baseline)"
  echo "New violations:"
  cat sqlfluff.new.txt
  exit 1
fi
echo "SQL lint: no new violations."
