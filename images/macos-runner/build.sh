#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

export LUME_TELEMETRY_ENABLED=false

IPSW=${IPSW:-latest}
IPSW_CACHE=${IPSW_CACHE:-$HOME/.cache/sand/ipsw}
BASE_VM=${BASE_VM:-macos-vanilla}
VM=${VM:-macos-runner}
XCODE_APPS=${XCODE_APPS:-/Applications/Xcode.app}
XCODE_CACHE=${XCODE_CACHE:-$HOME/.cache/sand/xcode}

vm_exists() {
  lume get "$1" >/dev/null 2>&1
}

resolve_ipsw() {
  if [ -f "$IPSW" ]; then
    echo "$IPSW"
    return
  fi
  local url=$IPSW
  if [ "$url" = latest ]; then
    url=$(lume ipsw | grep '^https://' | tail -1)
  fi
  local file
  file="$IPSW_CACHE/$(basename "$url")"
  if [ ! -f "$file" ]; then
    mkdir -p "$IPSW_CACHE"
    curl -fL -C - -o "$file.part" "$url" >&2
    mv "$file.part" "$file"
  fi
  echo "$file"
}

wait_for_ip() {
  local ip
  for _ in $(seq 1 150); do
    if ! kill -0 "$run_pid" 2>/dev/null; then
      cat "$run_log" >&2
      return 1
    fi
    ip=$(lume get "$VM" --format json 2>/dev/null | jq -r '.[0].ipAddress // empty')
    if [ -n "$ip" ]; then
      echo "$ip"
      return
    fi
    sleep 2
  done
  echo "timed out waiting for $VM to get an IP" >&2
  return 1
}

if ! vm_exists "$BASE_VM"; then
  lume create "$BASE_VM" --ipsw "$(resolve_ipsw)" --unattended tahoe
fi

if vm_exists "$VM"; then
  lume delete "$VM" --force
fi
lume clone "$BASE_VM" "$VM"

mkdir -p "$XCODE_CACHE"
xcode_names=()
for app in $XCODE_APPS; do
  name=$(basename "$app")
  if [ ! -f "$XCODE_CACHE/$name.tar" ]; then
    tar -cf "$XCODE_CACHE/$name.tar.part" -C "$(dirname "$app")" "$name"
    mv "$XCODE_CACHE/$name.tar.part" "$XCODE_CACHE/$name.tar"
  fi
  xcode_names+=("\"$name\"")
done

run_log=$(mktemp)
lume run "$VM" --display none --vnc disabled --shared-dir "$XCODE_CACHE:ro" >"$run_log" 2>&1 &
run_pid=$!
trap 'lume stop "$VM" --timeout 120 >/dev/null 2>&1 || true; wait "$run_pid" 2>/dev/null || true' EXIT

ip=$(wait_for_ip)
packer build \
  -var "host=$ip" \
  -var "xcode_apps=[$(IFS=,; echo "${xcode_names[*]}")]" \
  runner.pkr.hcl

for _ in $(seq 1 150); do
  kill -0 "$run_pid" 2>/dev/null || exit 0
  sleep 2
done
echo "$VM did not power off after shutdown" >&2
exit 1
