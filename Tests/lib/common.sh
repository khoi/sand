#!/bin/bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    fail "expected '$1' to equal '$2'"
  fi
}

assert_ne() {
  if [ "$1" = "$2" ]; then
    fail "expected '$1' to not equal '$2'"
  fi
}

assert_match() {
  if ! printf '%s' "$2" | grep -q -- "$1"; then
    fail "expected '$2' to match '$1'"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

require_file() {
  if [ ! -x "$1" ]; then
    fail "missing required executable: $1"
  fi
}

mktemp_dir() {
  mktemp -d
}

cleanup_dir() {
  local dir="$1"
  rm -rf "$dir"
}

init_defaults() {
  export SAND_E2E_IMAGE="${SAND_E2E_IMAGE:-ghcr.io/cirruslabs/ubuntu:latest}"
  export SAND_E2E_TIMEOUT_SEC="${SAND_E2E_TIMEOUT_SEC:-900}"
  export SAND_E2E_IP_WAIT_SEC="${SAND_E2E_IP_WAIT_SEC:-180}"
  export SAND_E2E_SSH_USER="${SAND_E2E_SSH_USER:-admin}"
  export SAND_E2E_SSH_PASSWORD="${SAND_E2E_SSH_PASSWORD:-admin}"
  export SAND_E2E_SSH_PORT="${SAND_E2E_SSH_PORT:-22}"
  export SAND_E2E_RUNNER_PREFIX="${SAND_E2E_RUNNER_PREFIX:-sand-e2e}"
}

ensure_e2e_deps() {
  require_file "$SAND_BIN"
  require_cmd tart
  require_cmd ssh
  require_cmd sshpass
  require_cmd python3
}

unique_runner_name() {
  local suffix
  suffix=$(date +%s)
  printf '%s-%s-%s\n' "$SAND_E2E_RUNNER_PREFIX" "$$" "$suffix"
}

write_config() {
  local path="$1"
  local runner_name="$2"
  cat >"$path" <<EOF_CONFIG
runners:
  - name: ${runner_name}
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
          echo "e2e provision"
          sleep 2
    healthCheck:
      command: "true"
      interval: 5
      delay: 5
EOF_CONFIG
}

tart_vm_state() {
  local name="$1"
  python3 - "$name" <<'PY'
import json
import subprocess
import sys
name = sys.argv[1]
output = subprocess.check_output(["tart", "list", "--format", "json"], text=True)
for entry in json.loads(output):
    if entry.get("Name") == name:
        running = entry.get("Running")
        if running is True:
            print("running")
        else:
            print("stopped")
        raise SystemExit(0)
print("missing")
PY
}

wait_for_vm_absent() {
  local name="$1"
  local timeout="$2"
  local start
  start=$(date +%s)
  while true; do
    local state
    state=$(tart_vm_state "$name")
    if [ "$state" = "missing" ]; then
      return 0
    fi
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      fail "timed out waiting for VM $name to disappear"
    fi
    sleep 5
  done
}

wait_for_vm_running() {
  local name="$1"
  local timeout="$2"
  local start
  start=$(date +%s)
  while true; do
    local state
    state=$(tart_vm_state "$name")
    if [ "$state" = "running" ]; then
      return 0
    fi
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      fail "timed out waiting for VM $name to be running"
    fi
    sleep 5
  done
}

wait_for_vm_restarted() {
  local name="$1"
  local timeout="$2"
  local start
  start=$(date +%s)
  local seen_running=1
  local seen_missing=0
  while true; do
    local state
    state=$(tart_vm_state "$name")
    case "$state" in
      running)
        if [ "$seen_missing" -eq 1 ]; then
          return 0
        fi
        seen_running=1
        ;;
      stopped|missing)
        if [ "$seen_running" -eq 1 ]; then
          seen_missing=1
        fi
        ;;
    esac
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      fail "timed out waiting for VM $name to restart"
    fi
    sleep 1
  done
}

run_with_timeout() {
  local timeout="$1"
  shift
  "$@" &
  local pid=$!
  local start
  start=$(date +%s)
  while kill -0 "$pid" >/dev/null 2>&1; do
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      fail "timed out running: $*"
    fi
    sleep 2
  done
  wait "$pid"
}

vm_ip() {
  local name="$1"
  tart ip "$name" --wait "$SAND_E2E_IP_WAIT_SEC"
}

ssh_exec() {
  local ip="$1"
  shift
  sshpass -p "$SAND_E2E_SSH_PASSWORD" ssh \
    -o ConnectTimeout=5 \
    -o LogLevel=ERROR \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -p "$SAND_E2E_SSH_PORT" \
    "${SAND_E2E_SSH_USER}@${ip}" \
    "$@"
}

wait_for_vm_file() {
  local ip="$1"
  local path="$2"
  local timeout="$3"
  local start
  start=$(date +%s)
  while true; do
    if ssh_exec "$ip" "test -f $path" >/dev/null 2>&1; then
      return 0
    fi
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      fail "timed out waiting for $path on $ip"
    fi
    sleep 2
  done
}

start_sand_run() {
  local config="$1"
  local log="$2"
  shift 2
  : >"$log"
  "$SAND_BIN" run --config "$config" "$@" >"$log" 2>&1 &
  echo $!
}

wait_for_process_exit() {
  local pid="$1"
  local timeout="$2"
  local start
  start=$(date +%s)
  while kill -0 "$pid" >/dev/null 2>&1; do
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      fail "timed out waiting for process $pid to exit"
    fi
    sleep 1
  done
  wait "$pid" >/dev/null 2>&1 || true
}

stop_process() {
  local pid="$1"
  local signal="${2:-TERM}"
  local timeout="${3:-20}"
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "-$signal" "$pid" >/dev/null 2>&1 || true
  fi
  local start
  start=$(date +%s)
  while kill -0 "$pid" >/dev/null 2>&1; do
    local now
    now=$(date +%s)
    if [ $((now - start)) -ge "$timeout" ]; then
      kill -KILL "$pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 1
  done
  wait "$pid" >/dev/null 2>&1 || true
}
