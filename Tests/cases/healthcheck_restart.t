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
          echo "e2e healthcheck provision ${runner}"
          sleep 60
    preRun: |
      echo "e2e healthcheck preRun ${runner}"
      date +%s%N > /tmp/e2e_boot_id
      touch /tmp/e2e_health_ok
    healthCheck:
      command: "test -f /tmp/e2e_health_ok"
      interval: 2
      delay: 1
EOF_CONFIG

cleanup() {
  cleanup_runner "${sand_pid:-}" "$runner" "$config" "$workdir"
}
trap cleanup EXIT

register_e2e_artifacts "$config" "$log"
sand_pid=$(start_sand_run "$config" "$log")

wait_for_vm_running "$runner" 180
ip=$(vm_ip "$runner")

wait_for_vm_file "$ip" /tmp/e2e_boot_id 60

boot_id=$(ssh_exec "$ip" "cat /tmp/e2e_boot_id" 2>/dev/null || true)
if [ -z "$boot_id" ]; then
  fail "failed to read initial boot id"
fi

ssh_exec "$ip" "rm -f /tmp/e2e_health_ok" >/dev/null 2>&1 || true

wait_for_vm_restarted "$runner" 180
wait_for_vm_running "$runner" 180
ip=$(vm_ip "$runner")
wait_for_vm_file "$ip" /tmp/e2e_boot_id 60
new_boot_id=$(ssh_exec "$ip" "cat /tmp/e2e_boot_id" 2>/dev/null || true)
if [ -z "$new_boot_id" ]; then
  fail "failed to read boot id after restart"
fi
if [ "$new_boot_id" = "$boot_id" ]; then
  fail "VM boot id did not change after restart"
fi

stop_process "$sand_pid" TERM 20
wait_for_vm_stopped_or_absent "$runner" 180
