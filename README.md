# sand

sand is a Swift CLI that runs ephemeral macOS VMs via Tart.

## Requirements

- macOS 14 or later
- Tart installed and available in PATH
- A VM image available locally or pullable from a registry

## Configuration

Create a `sand.yml` and run the CLI with `--config`.

```
vm:
  source:
    type: oci
    image: ghcr.io/cirruslabs/macos-runner:tahoe
  hardware:
    ramGb: 4
```

## Usage

```
swift run sand --config sand.yml
```

Press Ctrl+C to stop sand early.

To see OSLog output from sand, run with:

```
OS_LOG_LEVEL=debug OS_ACTIVITY_MODE=debug OS_ACTIVITY_DT_MODE=1 swift run sand --config sand.yml
```

## Behavior

Each run does the following:

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
stop + delete ephemeral
```

1. Pulls the OCI image if it is not already present locally.
2. Clones the source VM into a local VM named `ephemeral`.
3. Starts the VM headless.
4. Retrieves the VM IP address.
5. Stops and deletes the `ephemeral` VM.

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
