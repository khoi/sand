import Foundation
import Testing
@testable import sand

@Test
func parsesConfigAndExpandsPaths() throws {
    let yaml = """
    stopAfter: 1
    runnerCount: 2
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
    provisioner:
      type: github
      config:
        appId: 42
        organization: acme
        repository: repo
        privateKeyPath: ~/key.pem
        runnerName: runner-1
        extraLabels: [fast, arm64]
    """
    let url = try writeTempFile(contents: yaml)
    let config = try Config.load(path: url.path)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(config.stopAfter == 1)
    #expect(config.runnerCount == 2)
    #expect(config.vm?.hardware?.ramGb == 4)
    #expect(config.vm?.source.type == .local)
    #expect(config.vm?.source.resolvedSource == "file://\(home)/vm")
    #expect(config.vm?.mounts.first?.hostPath == "\(home)/cache")
    #expect(config.vm?.mounts.first?.guestFolder == "cache")
    #expect(config.vm?.mounts.first?.readOnly == true)
    #expect(config.vm?.mounts.first?.tag == "build")
    #expect(config.vm?.run.noGraphics == false)
    #expect(config.vm?.run.noClipboard == true)
    #expect(config.vm?.diskSizeGb == 80)
    #expect(config.vm?.ssh.user == "admin")
    #expect(config.vm?.ssh.password == "admin")
    #expect(config.vm?.ssh.port == 22)
    #expect(config.vm?.hardware?.display?.refit == true)
    #expect(config.provisioner?.type == .github)
    #expect(config.provisioner?.github?.organization == "acme")
    #expect(config.provisioner?.github?.repository == "repo")
    #expect(config.provisioner?.github?.extraLabels ?? [] == ["fast", "arm64"])
    #expect(config.provisioner?.github?.privateKeyPath.hasPrefix(home) ?? false)
}

@Test
func scriptProvisioner() throws {
    let yaml = """
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
    """
    let url = try writeTempFile(contents: yaml)
    let config = try Config.load(path: url.path)
    #expect(config.runnerCount == nil)
    #expect(config.vm?.hardware == nil)
    #expect(config.vm?.source.type == .oci)
    #expect(config.vm?.source.resolvedSource == "ghcr.io/acme/vm:latest")
    #expect(config.vm?.run.noGraphics == true)
    #expect(config.vm?.run.noClipboard == false)
    #expect(config.vm?.ssh.user == "runner")
    #expect(config.vm?.ssh.password == "secret")
    #expect(config.vm?.ssh.port == 2222)
    #expect(config.provisioner?.type == .script)
    #expect(config.provisioner?.script?.run.contains("Hello World") == true)
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
    #expect(config.runners?.count == 2)
    #expect(config.runners?.first?.name == "runner-a")
    #expect(config.runners?.first?.vm.source.resolvedSource == "file://\(home)/vm-a")
    #expect(config.runners?.last?.stopAfter == 2)
    #expect(config.runners?.last?.vm.source.resolvedSource == "file://\(home)/vm-b")
}
