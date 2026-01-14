#!/bin/bash
set -euo pipefail

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

skip() {
  printf 'SKIP: %s\n' "$1" >&2
  exit 0
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

run_cmd() {
  set +e
  RUN_OUTPUT=$("$@" 2>&1)
  RUN_STATUS=$?
  set -e
}
