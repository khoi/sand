# sand

sand is a Swift CLI that runs ephemeral macOS VMs via Tart and executes a provisioner inside each VM.

## Requirements

- macOS 14 or later
- Tart installed and available in PATH
- A VM image available locally or pullable from a registry

## Configuration

Create a `sand.yml` and run the CLI with `--config`. If `stopAfter` is omitted, sand loops forever.

```
stopAfter: 1
vm:
  source:
    type: oci
    image: ghcr.io/cirruslabs/macos-runner:tahoe
  hardware:
    ramGb: 4
  run:
    noGraphics: true
    noClipboard: false
  diskSizeGb: 80
  mounts:
    - hostPath: ~/ci-cache
      guestFolder: cache
      readOnly: false
      tag: build
provisioner:
  type: script
  config:
    run: |
      echo "Hello World"
      sleep 10
```

### VM options

- `vm.run.noGraphics` (default: true)
- `vm.run.noClipboard` (default: false)
- `vm.diskSizeGb` (optional)
- `vm.mounts[].tag` (optional)
- `vm.hardware.display.refit` (optional)

### GitHub Actions runner provisioner

```
stopAfter: 1
vm:
  source:
    type: oci
    image: ghcr.io/cirruslabs/macos-runner:tahoe
provisioner:
  type: github
  config:
    appId: 123456
    organization: my-org
    repository: my-repo
    privateKeyPath: ~/my-app.private-key.pem
    runnerName: runner-1
    extraLabels: [custom]
```

## Usage

```
swift run sand run --config sand.yml
```

sand runs forever by default. Set `stopAfter` to stop after N iterations, or stop it early with Ctrl+C. On Ctrl+C (SIGINT) or SIGTERM, sand attempts to stop and delete the current `ephemeral` VM before exiting.

Logs are emitted to stdout by default.

## Behavior

Each iteration does the following:

```
sand
  |
  v
prepare source (pull if missing)
  |
  v
clone -> run VM (ephemeral)
  |
  v
get IP
  |
  v
provision
  |-- script: tart exec /bin/bash -lc "<run>"
  `-- github: tart exec -> install + config runner -> run.sh
  |
  stop + delete ephemeral
```

1. Pulls the OCI image if it is not already present locally.
2. Clones the source VM into a local VM named `ephemeral`.
3. Starts the VM headless.
4. Retrieves the VM IP address.
5. Executes the provisioner inside the VM.
6. Stops and deletes the `ephemeral` VM.

If cleanup does not complete (for example, if Tart is unavailable), you can clean up manually:

```
tart stop ephemeral

tart delete ephemeral
```

## Tests

```
swift test
swift run sand run --config ./sample_config.yml
```

## Acknowledgements

Without these amazing projects, there would be no sand.

- https://github.com/cirruslabs/tart 
- https://github.com/traderepublic/Cilicon
