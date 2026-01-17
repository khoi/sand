#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
trap 'cleanup_dir "$workdir"' EXIT

runner=$(unique_runner_name)
key_file="$workdir/key.pem"
cache_dir="$workdir/runner-cache"
config="$workdir/config.yml"

printf 'key' >"$key_file"
mkdir -p "$cache_dir"

cat >"$config" <<EOF_CONFIG
runners:
  - name: ${runner}
    vm:
      source:
        type: oci
        image: ${SAND_E2E_IMAGE}
    provisioner:
      type: github
      config:
        appId: 1
        organization: acme
        repository: null
        privateKeyPath: ${key_file}
        runnerName: ${runner}
        runnerCache:
          hostPath: ${cache_dir}
          guestFolder: sand-cache
          readOnly: false
EOF_CONFIG

output=$("$SAND_BIN" validate --config "$config")
assert_match "Config is valid." "$output"
