# macOS runner image for Lume

`build.sh` creates `macos-vanilla` from the latest signed macOS restore image with Lume's unattended setup, clones it to `macos-runner`, and provisions the clone with Packer over SSH: passwordless sudo, Rosetta, Homebrew with git, git-lfs, gh, jq, yq, wget and xcodes, GitHub's SSH host keys, the Xcode apps you pass, the iOS simulator runtime and the Metal toolchain. The guest user is `lume` with password `lume`. Requires `lume`, `packer` and `jq` on the host.

```bash
XCODE_APPS="/Applications/Xcode-27.0.0.app" ./build.sh
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `XCODE_APPS` | `/Applications/Xcode.app` | Space-separated host Xcode apps to install; the first one is selected |
| `IPSW` | `latest` | `latest`, a restore image URL, or a local `.ipsw` path |
| `BASE_VM` | `macos-vanilla` | Unattended base VM, created once and reused |
| `VM` | `macos-runner` | Output VM, rebuilt from `BASE_VM` on every run |
| `IPSW_CACHE` | `~/.cache/sand/ipsw` | Download cache for restore images |
| `XCODE_CACHE` | `~/.cache/sand/xcode` | Tar archives of the Xcode apps, shared read-only with the VM |
