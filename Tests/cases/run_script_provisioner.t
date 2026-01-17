#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
runner=$(unique_runner_name)
config="$workdir/config.yml"
write_config "$config" "$runner"

cleanup() {
  "$SAND_BIN" destroy --config "$config" >/dev/null 2>&1 || true
  cleanup_dir "$workdir"
}
trap cleanup EXIT

run_with_timeout "$SAND_E2E_TIMEOUT_SEC" "$SAND_BIN" run --config "$config"
wait_for_vm_absent "$runner" 180
