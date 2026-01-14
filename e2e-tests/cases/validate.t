#!/bin/bash
set -euo pipefail

source "$ROOT/e2e-tests/lib/common.sh"

run_cmd "$SAND_BIN" validate --config "$ROOT/fixtures/sample_config.yml"
assert_eq 0 "$RUN_STATUS"
assert_match "Config is valid" "$RUN_OUTPUT"
