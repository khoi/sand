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
          echo "e2e crash provision ${runner}"
          sleep 60
    healthCheck:
      command: "true"
      interval: 2
      delay: 1
EOF_CONFIG

cleanup() {
  cleanup_runner "${sand_pid:-}" "$runner" "$config" "$workdir"
}
trap cleanup EXIT

sand_pid=$(start_sand_run "$config" "$log")

wait_for_vm_running "$runner" 180

tart stop "$runner" >/dev/null 2>&1 || true
wait_for_vm_restarted "$runner" 180

stop_process "$sand_pid" TERM 20
wait_for_vm_stopped_or_absent "$runner" 180
