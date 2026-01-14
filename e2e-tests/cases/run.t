#!/bin/bash
set -euo pipefail

source "$ROOT/e2e-tests/lib/common.sh"

printf '%s\n' "tart pull ghcr.io/cirruslabs/ubuntu:latest" >&2
tart pull ghcr.io/cirruslabs/ubuntu:latest

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
name1="e2e-runner-${RANDOM}-${RANDOM}"
name2="e2e-runner-${RANDOM}-${RANDOM}"

cat > "$dir/sand.yml" <<YAML
runners:
  - name: "$name1"
    stopAfter: 1
    vm:
      source:
        type: oci
        image: "ghcr.io/cirruslabs/ubuntu:latest"
      mounts:
        - hostPath: "$dir"
          guestFolder: "/mnt/host"
      ssh:
        user: admin
        password: admin
        port: 22
    provisioner:
      type: script
      config:
        run: |
          mkdir -p /mnt/host
          printf 'Hello World\n' >> /mnt/host/out-1.txt
    healthCheck:
      command: "true"
  - name: "$name2"
    stopAfter: 2
    vm:
      source:
        type: oci
        image: "ghcr.io/cirruslabs/ubuntu:latest"
      mounts:
        - hostPath: "$dir"
          guestFolder: "/mnt/host"
      ssh:
        user: admin
        password: admin
        port: 22
    provisioner:
      type: script
      config:
        run: |
          mkdir -p /mnt/host
          printf 'Hello World\n' >> /mnt/host/out-2.txt
    healthCheck:
      command: "true"
YAML

run_cmd "$SAND_BIN" run --config "$dir/sand.yml"
if [ "$RUN_STATUS" -ne 0 ]; then
  printf '%s\n' "$RUN_OUTPUT" >&2
  tart list >&2 || true
  list=$(tart list --quiet 2>/dev/null || true)
  printf '%s\n' "$list" >&2
  printf '%s\n' "$list" | grep -qx "$name1" && tart get "$name1" >&2 || true
  printf '%s\n' "$list" | grep -qx "$name2" && tart get "$name2" >&2 || true
  fail "sand run exited $RUN_STATUS"
fi

output1="$dir/out-1.txt"
output2="$dir/out-2.txt"
[ -f "$output1" ] || fail "expected output file at $output1"
[ -f "$output2" ] || fail "expected output file at $output2"
count1=$(grep -c "Hello World" "$output1" || true)
count2=$(grep -c "Hello World" "$output2" || true)
assert_eq 1 "$count1"
assert_eq 2 "$count2"

list=$(tart list --quiet || true)
printf '%s\n' "$list" | grep -qx "$name1" && fail "expected $name1 to be cleaned up"
printf '%s\n' "$list" | grep -qx "$name2" && fail "expected $name2 to be cleaned up"
