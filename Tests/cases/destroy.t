#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
runner=$(unique_runner_name)
config="$workdir/config.yml"
write_config "$config" "$runner"

trap 'cleanup_dir "$workdir"' EXIT

"$SAND_BIN" destroy --config "$config"
wait_for_vm_absent "$runner" 60
