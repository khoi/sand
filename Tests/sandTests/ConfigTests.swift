import Foundation
import Testing
@testable import sand

@Test
func parsesConfigAndExpandsPaths() throws {
    let yaml = """
    runners:
      - name: runner-1
        stopAfter: 1
        vm:
          source:
            type: local
            path: ~/vm
          hardware:
            ramGb: 4
            display:
              width: 1920
              height: 1200
              unit: px
              refit: true
          mounts:
            - hostPath: ~/cache
              guestFolder: cache
              readOnly: true
              tag: build
          run:
            noGraphics: false
            noClipboard: true
          diskSizeGb: 80
          ssh:
            user: admin
            password: admin
            port: 22
            connectMaxRetries: 20
        provisioner:
          type: github
          config:
            appId: 42
            organization: acme
            repository: repo
            privateKeyPath: ~/key.pem
            runnerName: runner-1
            extraLabels: [fast, arm64]
        healthCheck:
          command: "pgrep -f run.sh"
          interval: 15
          delay: 45
    """
    let url = try writeTempFile(contents: yaml)
    let config = try Config.load(path: url.path)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(config.runners.count == 1)
    #expect(config.runners.first?.stopAfter == 1)
    #expect(config.runners.first?.vm.hardware?.ramGb == 4)
    #expect(config.runners.first?.vm.source.type == .local)
    #expect(config.runners.first?.vm.source.resolvedSource == "file://\(home)/vm")
    #expect(config.runners.first?.vm.mounts.first?.hostPath == "\(home)/cache")
    #expect(config.runners.first?.vm.mounts.first?.guestFolder == "cache")
    #expect(config.runners.first?.vm.mounts.first?.readOnly == true)
    #expect(config.runners.first?.vm.mounts.first?.tag == "build")
    #expect(config.runners.first?.vm.run.noGraphics == false)
    #expect(config.runners.first?.vm.run.noClipboard == true)
    #expect(config.runners.first?.vm.diskSizeGb == 80)
    #expect(config.runners.first?.vm.ssh.user == "admin")
    #expect(config.runners.first?.vm.ssh.password == "admin")
    #expect(config.runners.first?.vm.ssh.port == 22)
    #expect(config.runners.first?.vm.ssh.connectMaxRetries == 20)
    #expect(config.runners.first?.vm.hardware?.display?.refit == true)
    #expect(config.runners.first?.provisioner.type == .github)
    #expect(config.runners.first?.provisioner.github?.organization == "acme")
    #expect(config.runners.first?.provisioner.github?.repository == "repo")
    #expect(config.runners.first?.provisioner.github?.extraLabels ?? [] == ["fast", "arm64"])
    #expect(config.runners.first?.provisioner.github?.privateKeyPath.hasPrefix(home) ?? false)
    #expect(config.runners.first?.healthCheck?.command == "pgrep -f run.sh")
    #expect(config.runners.first?.healthCheck?.interval == 15)
    #expect(config.runners.first?.healthCheck?.delay == 45)
}

@Test
func scriptProvisioner() throws {
    let yaml = """
    runners:
      - name: runner-1
        vm:
          source:
            type: oci
            image: ghcr.io/acme/vm:latest
          ssh:
            user: runner
            password: secret
            port: 2222
        provisioner:
          type: script
          config:
            run: |
              echo "Hello World"
              sleep 1
        healthCheck:
          command: "true"
    """
    let url = try writeTempFile(contents: yaml)
    let config = try Config.load(path: url.path)
    #expect(config.runners.count == 1)
    #expect(config.runners.first?.vm.hardware == nil)
    #expect(config.runners.first?.vm.source.type == .oci)
    #expect(config.runners.first?.vm.source.resolvedSource == "ghcr.io/acme/vm:latest")
    #expect(config.runners.first?.vm.run.noGraphics == true)
    #expect(config.runners.first?.vm.run.noClipboard == false)
    #expect(config.runners.first?.vm.ssh.user == "runner")
    #expect(config.runners.first?.vm.ssh.password == "secret")
    #expect(config.runners.first?.vm.ssh.port == 2222)
    #expect(config.runners.first?.vm.ssh.connectMaxRetries == nil)
    #expect(config.runners.first?.provisioner.type == .script)
    #expect(config.runners.first?.provisioner.script?.run.contains("Hello World") == true)
    #expect(config.runners.first?.healthCheck?.interval == 30)
    #expect(config.runners.first?.healthCheck?.delay == 60)
}

@Test
func explicitRunnersConfig() throws {
    let yaml = """
    runners:
      - name: runner-a
        vm:
          source:
            type: local
            path: ~/vm-a
          ssh:
            user: admin
            password: admin
            port: 22
        provisioner:
          type: script
          config:
            run: echo "A"
        healthCheck:
          command: "true"
      - name: runner-b
        stopAfter: 2
        vm:
          source:
            type: local
            path: ~/vm-b
          ssh:
            user: admin
            password: admin
            port: 22
        provisioner:
          type: script
          config:
            run: echo "B"
    """
    let url = try writeTempFile(contents: yaml)
    let config = try Config.load(path: url.path)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(config.runners.count == 2)
    #expect(config.runners.first?.name == "runner-a")
    #expect(config.runners.first?.vm.source.resolvedSource == "file://\(home)/vm-a")
    #expect(config.runners.last?.stopAfter == 2)
    #expect(config.runners.last?.vm.source.resolvedSource == "file://\(home)/vm-b")
    #expect(config.runners.first?.healthCheck?.command == "true")
}
