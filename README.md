# sand

Self-hosted macOS CI Runners powered by Tart - Apple's Virtualization framework.

## Requirements

- macOS running on Apple Silicon machines.
- Tart installed and available in PATH (https://tart.run/quick-start/)

## Install

```
brew tap khoi/sand
brew install sand
```

## Usage

```
sand run --config config.yml
sand destroy --config config.yml
```

## Logs

sand logs to macOS default logging system using `os_log`. To see the log

```
log stream --predicate 'subsystem == "sand"' --info --debug
```

## Configuration

Create a `config.yml` and run the CLI with `--config`. 

### GitHub Actions runner provisioner
```
runners:
  - name: runner-1
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
    healthCheck:
      command: "pgrep -fl /Users/admin/actions-runner/run.sh"
      interval: 30
      delay: 60
```

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

Full configurations keys can be found at [fixtures/sample_full_config.yml](fixtures/sample_full_config.yml)

## Acknowledgements

- https://github.com/cirruslabs/tart - doing all the heavy lifting interacting with VMs.
- https://github.com/traderepublic/Cilicon - sand is heavily inspired by Cilicon
