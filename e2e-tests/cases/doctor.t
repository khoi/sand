#!/bin/bash
set -euo pipefail

source "$ROOT/e2e-tests/lib/common.sh"

run_cmd "$SAND_BIN" doctor
assert_eq 0 "$RUN_STATUS"
assert_match "sand doctor" "$RUN_OUTPUT"
