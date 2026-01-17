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

ssh_exec "$ip" "rm -f /tmp/e2e_health_ok" >/dev/null 2>&1 || true

start=$(date +%s)
while true; do
  state=$(tart_vm_state "$runner")
  if [ "$state" = "running" ]; then
    ip=$(tart ip "$runner" --wait 5 2>/dev/null || true)
    if [ -n "$ip" ]; then
      new_boot_id=$(ssh_exec "$ip" "cat /tmp/e2e_boot_id" 2>/dev/null || true)
      if [ -n "$new_boot_id" ] && [ "$new_boot_id" != "$boot_id" ]; then
        break
      fi
    fi
  fi
  now=$(date +%s)
  if [ $((now - start)) -ge 180 ]; then
    fail "timed out waiting for VM to restart"
  fi
  sleep 2
done

stop_process "$sand_pid" TERM 20
wait_for_vm_stopped_or_absent "$runner" 180
