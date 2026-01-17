#!/bin/bash
set -euo pipefail

source "$ROOT/Tests/lib/common.sh"

init_defaults
ensure_e2e_deps

if [ -n "${SAND_E2E_SKIP_DOCTOR:-}" ]; then
  printf '%s\n' "skipping doctor test" >&2
  exit 0
fi

"$SAND_BIN" doctor
