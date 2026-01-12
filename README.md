# sand

sand is a Swift CLI that runs ephemeral macOS VMs via Tart and executes a provisioner on each VM. The provisioner can be a script (run inside the VM with tart exec) or a GitHub Actions runner setup (run over SSH).

## Requirements

- macOS 14 or later
- Tart installed and available in PATH
- A VM image available locally or pullable from a registry

## Configuration

Create a `sand.yml` and run the CLI with `--config`.

### Script provisioner

```
source: ghcr.io/cirruslabs/macos-tahoe-xcode:latest
provisioner:
  type: script
  config:
    run: |
      echo "Hello World"
      sleep 10
ssh:
  username: admin
  password: admin
```

### GitHub Actions runner provisioner

```
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
ssh:
  username: admin
  password: admin
```

## Usage

```
swift run sand --config sand.yml
```

sand runs an infinite loop. Stop it with Ctrl+C.

## Behavior

Each loop iteration does the following:

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
  `-- github: ssh -> install + config runner -> run.sh
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
   - GitHub provisioner uses SSH to install and run the GitHub Actions runner.
6. Stops and deletes the `ephemeral` VM.

If the process is interrupted, you can clean up manually:

```
tart stop ephemeral

tart delete ephemeral
```

## Tests

```
swift test
```

## Acknowledgements

Without these amazing projects, there would be no sand.

- https://github.com/cirruslabs/tart 
- https://github.com/traderepublic/Cilicon
