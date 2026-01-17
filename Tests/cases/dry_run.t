#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
runner=$(unique_runner_name)
config="$workdir/config.yml"

cat >"$config" <<EOF_CONFIG
runners:
  - name: ${runner}
    stopAfter: 1
    vm:
      source:
        type: oci
        image: ${SAND_E2E_IMAGE}
      ssh:
        user: ${SAND_E2E_SSH_USER}
        password: ${SAND_E2E_SSH_PASSWORD}
        port: ${SAND_E2E_SSH_PORT}
      run:
        noGraphics: true
    provisioner:
      type: script
      config:
        run: |
          echo "e2e dry run ${runner}"
EOF_CONFIG

cleanup() {
  cleanup_dir "$workdir"
}
trap cleanup EXIT

run_with_timeout "$SAND_E2E_TIMEOUT_SEC" "$SAND_BIN" run --dry-run --config "$config"

state=$(tart_vm_state "$runner")
assert_eq "missing" "$state"
