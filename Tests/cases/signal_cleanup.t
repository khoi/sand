#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
log="$workdir/sand.log"

cleanup() {
  cleanup_runner "${sand_pid:-}" "" "${config:-}" "$workdir"
}
trap cleanup EXIT

run_signal_case() {
  local signal="$1"
  local runner="$2"
  local config_path="$3"

  cat >"$config_path" <<EOF_CONFIG
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
          echo "e2e signal provision ${runner}"
          sleep 60
    healthCheck:
      command: "true"
      interval: 5
      delay: 1
EOF_CONFIG

  sand_pid=$(start_sand_run "$config_path" "$log")
  wait_for_vm_running "$runner" 180

  stop_process "$sand_pid" "$signal" 20
  wait_for_vm_stopped_or_absent "$runner" 180
}

runner_int=$(unique_runner_name)
config="$workdir/config-int.yml"
run_signal_case INT "$runner_int" "$config"

runner_term=$(unique_runner_name)
config="$workdir/config-term.yml"
run_signal_case TERM "$runner_term" "$config"
