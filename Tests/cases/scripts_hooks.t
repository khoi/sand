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
          echo "e2e provision ${runner}"
          touch /tmp/e2e_provision
          sleep 5
    preRun: |
      echo "e2e preRun ${runner}"
      touch /tmp/e2e_pre
    postRun: |
      echo "e2e postRun ${runner}"
      touch /tmp/e2e_post
      sleep 5
    healthCheck:
      command: "true"
      interval: 5
      delay: 2
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
ip=$(vm_ip "$runner")

wait_for_vm_file "$ip" /tmp/e2e_pre 60
wait_for_vm_file "$ip" /tmp/e2e_provision 120
wait_for_vm_file "$ip" /tmp/e2e_post 180

wait_for_process_exit "$sand_pid" "$SAND_E2E_TIMEOUT_SEC"
wait_for_vm_absent "$runner" 180
