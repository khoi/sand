# sand

Self-hosted macOS CI Runners powered by Tart - Apple's Virtualization framework.

## Requirements

- macOS 15+ running on Apple Silicon machines.
- Tart installed and available in PATH 
- sand uses tart. it helps understanding tart before using sand (https://tart.run/quick-start/)

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

## Local test suite

To run the local bash e2e tests (no CI):

```
./Tests/run
```

These tests spin up real VMs and require `tart`, `ssh`, and `sshpass` on your machine. See `Tests/README.md` for environment overrides (image, timeout, SSH creds, etc).

## Start up on boot

To make sand run on boot, u can leverage launchctl as an option

1) Create a LaunchAgent plist at `~/Library/LaunchAgents/io.khoi.sand.plist`:

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>io.khoi.sand</string>
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/sand</string>
    <string>run</string>
    <string>--config</string>
    <string>/Users/yourname/sand.yml</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WorkingDirectory</key>
  <string>/Users/yourname</string>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/Users/yourname/Library/Logs/sand.launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/yourname/Library/Logs/sand.launchd.err.log</string>
</dict>
</plist>
```

2) Load it (modern launchctl):

```
launchctl enable gui/$(id -u)/com.khoi.sand
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.khoi.sand.plist
launchctl kickstart -k gui/$(id -u)/com.khoi.sand
launchctl print gui/$(id -u)/com.khoi.sand
```

## Logs

sand logs to macOS default logging system using `os_log`. To see the log

```
log show --predicate "subsystem == \"sand\"" --last 1h --info --debug
log stream --predicate 'subsystem == "sand"' --debug --info --style compact --color always
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

### Pre/Post run hooks

`preRun` and `postRun` execute commands over SSH inside the VM before and after the provisioner runs. If a command exits non-zero, the run fails.

```
runners:
  - name: runner-1
    vm:
      source:
        type: oci
        image: "ghcr.io/cirruslabs/ubuntu:latest"
    provisioner:
      type: script
      config:
        run: echo "provision"
    preRun: |
      echo "before provisioner"
    postRun: |
      echo "after provisioner"
```

If `healthCheck` is omitted, sand runs `echo healthcheck` every 30s after a 60s delay.

Full configurations keys can be found at [fixtures/sample_full_config.yml](fixtures/sample_full_config.yml)

## Acknowledgements

- https://github.com/cirruslabs/tart - doing all the heavy lifting interacting with VMs.
- https://github.com/traderepublic/Cilicon - sand is heavily inspired by Cilicon
