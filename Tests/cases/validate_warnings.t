#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
trap 'cleanup_dir "$workdir"' EXIT

runner=$(unique_runner_name)
config="$workdir/warn.yml"
cat >"$config" <<EOF_CONFIG
runners:
  - name: ${runner}
    stopAfter: 0
    vm:
      source:
        type: oci
        image: ${SAND_E2E_IMAGE}
      ssh:
        user: ${SAND_E2E_SSH_USER}
        password: ${SAND_E2E_SSH_PASSWORD}
        port: ${SAND_E2E_SSH_PORT}
      mounts:
        - host: /path/does/not/exist
          name: e2e
          mode: ro
      cache:
        host: /tmp/runner-cache
        name: sand-cache
    provisioner:
      type: script
      config:
        run: "echo warn"
EOF_CONFIG

output=$("$SAND_BIN" validate --config "$config")
assert_match "warning" "$output"
assert_match "stopAfter" "$output"
assert_match "vm.cache is set but provisioner is not github" "$output"
