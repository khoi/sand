# sand

Self-hosted macOS CI Runners powered by Tart - Apple's Virtualization framework.

## Requirements

- macOS 15+ running on Apple Silicon machines.
- Tart installed and available in PATH
- sand uses tart. it helps understanding tart before using sand (https://tart.run/quick-start/)

## Caveats

macOS DHCP leases last 24 hours by default, causing IP exhaustion if you run more than ~253 VMs per day. To reduce lease time to 10 minutes:

```
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.InternetSharing.default.plist bootpd -dict DHCPLeaseTimeSecs -int 600
```

## Install

```
brew trust khoi/sand openai/tools
brew tap khoi/sand
brew tap openai/tools
brew install sand
```

Homebrew only loads formulae from taps you have trusted; the second tap provides Tart.

## Usage

```
sand run --config config.yml
sand destroy --config config.yml
sand run --dry-run --config config.yml
```

## Local test suite

To run the local bash e2e tests (no CI):

```
./Tests/run
```

These tests spin up real VMs and require `tart`, `ssh`, and `sshpass` on your machine. See `Tests/README.md` for environment overrides (image, timeout, SSH creds, etc).

## Start up on boot

Create your config at `~/sand.yml`, then let Homebrew manage a LaunchAgent for it:

```
brew services start sand
```

The service restarts sand if it exits, runs it as an interactive process so launchd doesn't throttle its CPU and I/O (or the VMs it starts), and writes output to `~/Library/Logs/sand.log`. Stop it with `brew services stop sand`.

## Logs

sand logs to macOS default logging system using `os_log`. To see the log

```
log show --predicate "subsystem == \"sand\"" --last 1h --info --debug
log stream --predicate 'subsystem == "sand"' --debug --info --style compact --color always
```

You can also write logs to a file:

```
sand run --config config.yml --log-file /tmp/sand.log
```

## Configuration

Create a `config.yml` and run the CLI with `--config`. 

### VM source

`vm.source` selects the base VM that sand clones for each ephemeral runner.

OCI image pulled from a registry:

```
vm:
  source:
    type: oci
    image: ghcr.io/cirruslabs/macos-runner:tahoe
```

Existing local Tart VM, referenced by name (as shown by `tart list`):

```
vm:
  source:
    type: local
    name: expo-runner
```

For `local` sources sand skips the registry pull and clones the named VM directly (`tart clone <name> <ephemeral>`), so the VM must already exist in `~/.tart/vms`.

To refresh OCI images daily, add this at the top level of your configuration:

```yaml
imageRefreshIntervalSeconds: 86400
```

Sand pulls each image before its first VM creation after startup, then before the next VM creation after the interval expires. Runners sharing an image share the refresh schedule. There is no background timer: if no new VM is needed, the refresh waits. Tart checks for updates and manages downloads and cache cleanup.

Image preparation and cloning are serialized within one sand process; existing VMs and jobs keep running during a pull. Other sand processes and manual Tart commands are not coordinated. If a refresh fails and the image is still cached, sand uses it and retries on the next VM creation after five minutes (or the configured interval if shorter). Without a cached image, startup fails.

Omit the setting to pull only missing images. Local sources are never pulled. The refresh schedule resets on restart; `--dry-run` only prepares missing images.

### GitHub Actions setup

1) Create a GitHub App and grant `Self-hosted runners` permission set to `Read & Write` at the organization level. https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app
2) Install the app on the organization or the specific repository you want to run against.
3) Download the private key and set `appId`, `organization`, `repository` (optional), and `privateKeyPath` in your config.
4) Optionally set `runnerGroup` to register organization-level runners into a runner group (requires omitting `repository`).

Each VM boot registers the runner as `<runnerName>-<5 hex chars>` so a VM killed mid-session never collides with the next boot's GitHub session. Sand deletes that registration from GitHub when it tears the VM down.

### GitHub Actions runner provisioner
```
runners:
  - name: runner-1
    vm:
      source:
        type: oci
        image: ghcr.io/cirruslabs/macos-runner:tahoe
      cache:
        host: ~/.cache/sand/actions-runner
    provisioner:
      type: github
      config:
        appId: 123456
        organization: my-org
        repository: my-repo
        privateKeyPath: ~/my-app.private-key.pem
        runnerName: runner-1
    healthCheck:
      command: "pgrep -fl /Users/admin/actions-runner/run.sh"
      interval: 30
      delay: 60
```

Sand downloads the Actions runner on the host, checks it against the SHA-256 digest GitHub publishes for the release, and copies the verified tarball into each VM over `scp`. The guest never downloads the runner and never gets write access to the cache, so a job cannot tamper with the runner used by later VMs.

Verified tarballs are kept in `vm.cache.host` (default `~/.cache/sand/actions-runner`), with a `.sha256` file next to each and the three newest versions retained per platform. Sand checks for a new runner release once a day; if GitHub is unreachable it falls back to the newest verified tarball in the cache.

Common pitfalls:
- `vm.cache.host` must be a directory (missing paths are created; file paths are rejected).
- `vm.cache` is ignored unless the provisioner type is `github`.
- `scp` must be available on the host.

### Custom provisioner script

```
runners:
  - name: runner-1
    vm:
      source:
        type: oci
        image: "ghcr.io/cirruslabs/ubuntu:latest"
      hardware:
        ramGb: 4
      ssh:
        user: admin
        password: admin
        port: 22
    provisioner:
      type: script
      config:
        run: |
          echo "Hello World" && sleep 10
    healthCheck:
      command: "true"
```

If `healthCheck` is omitted, sand runs `echo healthcheck` every 30s after a 60s delay.

### VM run options

`vm.run` controls how each VM is booted via `tart run`:

```
runners:
  - name: runner-1
    vm:
      run:
        noGraphics: true    # default true; pass --no-graphics
        noClipboard: false  # default false; pass --no-clipboard when true
        nested: false       # default false; pass --nested for nested virtualization
        rootDiskOpts: null  # optional; passed as --root-disk-opts
```

Set `nested: true` to boot the VM with `tart run --nested`, enabling nested virtualization inside the guest. This requires an Apple Silicon host and guest that support it (see the [Tart docs](https://tart.run/)).

Set `rootDiskOpts` to tune the root disk with `tart run --root-disk-opts`. Since runner VMs are thrown away after each job, `caching=cached,sync=none` trades crash consistency for much faster guest fsync.

Full configurations keys can be found at [fixtures/sample_full_config.yml](fixtures/sample_full_config.yml) or [fixtures/sample_on_prod.yml](fixtures/sample_on_prod.yml)

## Acknowledgements

- https://github.com/cirruslabs/tart - doing all the heavy lifting interacting with VMs.
- https://github.com/traderepublic/Cilicon - sand is heavily inspired by Cilicon
