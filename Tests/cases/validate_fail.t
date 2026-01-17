#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
trap 'cleanup_dir "$workdir"' EXIT

config="$workdir/bad.yml"
cat >"$config" <<'EOF_CONFIG'
runners:
  - name: ""
    vm:
      source:
        type: oci
    provisioner:
      type: script
      config:
        run: ""
EOF_CONFIG

if "$SAND_BIN" validate --config "$config"; then
  fail "expected validate to fail with invalid config"
fi
