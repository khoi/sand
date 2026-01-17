#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

workdir=$(mktemp_dir)
trap 'cleanup_dir "$workdir"' EXIT

cat >"$workdir/sand.yml" <<'EOF_CONFIG'
runners: []
EOF_CONFIG

set +e
output=$(cd "$workdir" && "$SAND_BIN" doctor 2>&1)
status=$?
set -e

if [ "$status" -eq 0 ]; then
  fail "expected doctor to fail with invalid config"
fi

assert_match "sand doctor found issues" "$output"
assert_match "runners must not be empty" "$output"
