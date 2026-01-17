#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
trap 'cleanup_dir "$workdir"' EXIT

runner=$(unique_runner_name)
config="$workdir/config.yml"
write_config "$config" "$runner"

"$SAND_BIN" validate --config "$config"
