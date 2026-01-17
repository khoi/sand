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
          sleep 3
          touch /tmp/e2e_health_ok
          sleep 20
    preRun: |
      date +%s%N > /tmp/e2e_boot_id
    healthCheck:
      command: "test -f /tmp/e2e_health_ok"
      interval: 5
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
ip=$(vm_ip "$runner")

wait_for_vm_file "$ip" /tmp/e2e_boot_id 60
boot_id=$(ssh_exec "$ip" "cat /tmp/e2e_boot_id" 2>/dev/null || true)
if [ -z "$boot_id" ]; then
  fail "failed to read initial boot id"
fi

wait_for_vm_file "$ip" /tmp/e2e_health_ok 60
sleep 8

boot_id_after=$(ssh_exec "$ip" "cat /tmp/e2e_boot_id" 2>/dev/null || true)
if [ -z "$boot_id_after" ]; then
  fail "failed to read boot id after healthcheck"
fi
if [ "$boot_id_after" != "$boot_id" ]; then
  fail "VM restarted during startup grace window"
fi

stop_process "$sand_pid" TERM 20
wait_for_vm_absent "$runner" 180
