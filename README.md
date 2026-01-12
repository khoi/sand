# sand

sand is a Swift CLI that runs ephemeral macOS VMs via Tart and executes a provisioner on each VM. The provisioner can be a script or a GitHub Actions runner setup, both run inside the VM with tart exec.

## Requirements

- macOS 14 or later
- Tart installed and available in PATH
- A VM image available locally or pullable from a registry

## Configuration

Create a `sand.yml` and run the CLI with `--config`. If `stopAfter` is omitted, sand loops forever.

### Script provisioner

```
stopAfter: 1
source: ghcr.io/cirruslabs/macos-tahoe-xcode:latest
provisioner:
  type: script
  config:
    run: |
      echo "Hello World"
      sleep 10
```

### GitHub Actions runner provisioner

```
stopAfter: 1
source: ghcr.io/cirruslabs/macos-runner:tahoe
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
swift run sand --config sand.yml
```

sand runs forever by default. Set `stopAfter` to stop after N iterations, or stop it early with Ctrl+C.

To see OSLog output from sand, run with:

```
OS_LOG_LEVEL=debug OS_ACTIVITY_MODE=debug OS_ACTIVITY_DT_MODE=1 swift run sand --config sand.yml
```

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
  v
stop + delete ephemeral
  |
  v
repeat
```

1. Pulls the OCI image if it is not already present locally.
2. Clones the source VM into a local VM named `ephemeral`.
3. Starts the VM headless.
4. Retrieves the VM IP address.
5. Executes the provisioner:
   - Script provisioner uses `tart exec` to run the script in the VM.
   - Script output is forwarded to sand stdout/stderr after the command finishes.
   - GitHub provisioner uses `tart exec` to install and run the GitHub Actions runner.
6. Stops and deletes the `ephemeral` VM.

If the process is interrupted, you can clean up manually:

```
tart stop ephemeral

tart delete ephemeral
```

## Tests

```
swift test
swift run sand --config ./sample_config.yml # Replace with your an existing image to avoid cloning
```

## Acknowledgements

Without these amazing projects, there would be no sand.

- https://github.com/cirruslabs/tart 
- https://github.com/traderepublic/Cilicon
