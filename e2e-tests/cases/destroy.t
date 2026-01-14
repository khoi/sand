#!/bin/bash
set -euo pipefail

source "$ROOT/e2e-tests/lib/common.sh"

run_cmd "$SAND_BIN" destroy --config "$ROOT/fixtures/sample_config.yml"
assert_eq 0 "$RUN_STATUS"
