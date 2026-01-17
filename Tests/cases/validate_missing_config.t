#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

missing_path="/tmp/sand-missing-$$.yml"

set +e
output=$("$SAND_BIN" validate --config "$missing_path" 2>&1)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  fail "expected validate to fail for missing config"
fi

assert_match "Config file not found" "$output"
