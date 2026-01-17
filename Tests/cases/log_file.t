#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
runner=$(unique_runner_name)
config="$workdir/config.yml"
log="$workdir/sand.log"
export SAND_E2E_CONFIG="$config"
export SAND_E2E_LOG="$log"

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
          echo "e2e log file ${runner}"
          sleep 2
    healthCheck:
      command: "true"
      interval: 5
      delay: 1
EOF_CONFIG

cleanup() {
  "$SAND_BIN" destroy --config "$config" >/dev/null 2>&1 || true
  cleanup_dir "$workdir"
}
trap cleanup EXIT

run_with_timeout "$SAND_E2E_TIMEOUT_SEC" "$SAND_BIN" run --config "$config" --log-file "$log"

if [ ! -s "$log" ]; then
  fail "log file not created"
fi

if ! grep -q "host.${runner}.*boot VM" "$log"; then
  fail "log file missing boot entry"
fi
