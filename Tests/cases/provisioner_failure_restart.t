#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
runner=$(unique_runner_name)
config="$workdir/config.yml"
log="$workdir/sand.log"

cat >"$config" <<EOF_CONFIG
runners:
  - name: ${runner}
    stopAfter: null
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
          echo "e2e provisioner fail ${runner}"
          sleep 2
          exit 1
    healthCheck:
      command: "true"
      interval: 2
      delay: 1
EOF_CONFIG

cleanup() {
  if [ -n "${sand_pid:-}" ]; then
    stop_process "$sand_pid" TERM 10 || true
  fi
  "$SAND_BIN" destroy --config "$config" >/dev/null 2>&1 || true
  cleanup_dir "$workdir"
}
trap cleanup EXIT

sand_pid=$(start_sand_run "$config" "$log")

wait_for_vm_running "$runner" 180
wait_for_vm_restarted "$runner" 180

stop_process "$sand_pid" TERM 20
wait_for_vm_stopped_or_absent "$runner" 180
