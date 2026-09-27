import Foundation
import XCTest
@testable import sand

final class ConfigTests: XCTestCase {
    func testParsesConfigAndExpandsPaths() throws {
        let yaml = """
        runners:
          - name: runner-1
            stopAfter: 1
            vm:
              source:
                type: local
                name: my-vm
              hardware:
                ramGb: 4
                display:
                  width: 1920
                  height: 1200
                  unit: px
                  refit: true
              mounts:
                - host: ~/cache
                  mode: ro
              run:
                noGraphics: false
                noClipboard: true
                nested: true
                rootDiskOpts: caching=cached,sync=none
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
            preRun: |
              echo "pre-run"
            postRun: |
              echo "post-run"
            healthCheck:
              command: "pgrep -f run.sh"
              interval: 15
              delay: 45
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(config.runners.count, 1)
        XCTAssertEqual(config.runners.first?.stopAfter, 1)
        XCTAssertEqual(config.runners.first?.vm.hardware?.ramGb, 4)
        XCTAssertEqual(config.runners.first?.vm.source.type, .local)
        XCTAssertEqual(config.runners.first?.vm.source.resolvedSource, "my-vm")
        XCTAssertEqual(config.runners.first?.vm.mounts.first?.hostPath, "\(home)/cache")
        XCTAssertEqual(Config.resolveMountName(
            hostPath: config.runners.first?.vm.mounts.first?.hostPath ?? "",
            name: config.runners.first?.vm.mounts.first?.name
        ), "cache")
        XCTAssertEqual(config.runners.first?.vm.mounts.first?.mode, .ro)
        XCTAssertEqual(config.runners.first?.vm.run.noGraphics, false)
        XCTAssertEqual(config.runners.first?.vm.run.noClipboard, true)
        XCTAssertEqual(config.runners.first?.vm.run.nested, true)
        XCTAssertEqual(config.runners.first?.vm.run.rootDiskOpts, "caching=cached,sync=none")
        XCTAssertEqual(config.runners.first?.vm.diskSizeGb, 80)
        XCTAssertEqual(config.runners.first?.vm.ssh.user, "admin")
        XCTAssertEqual(config.runners.first?.vm.ssh.password, "admin")
        XCTAssertEqual(config.runners.first?.vm.ssh.port, 22)
        XCTAssertEqual(config.runners.first?.vm.ssh.connectMaxRetries, 20)
        XCTAssertEqual(config.runners.first?.vm.hardware?.display?.refit, true)
        XCTAssertEqual(config.runners.first?.provisioner.type, .github)
        XCTAssertEqual(config.runners.first?.provisioner.github?.organization, "acme")
        XCTAssertEqual(config.runners.first?.provisioner.github?.repository, "repo")
        XCTAssertEqual(config.runners.first?.provisioner.github?.extraLabels ?? [], ["fast", "arm64"])
        XCTAssertTrue(config.runners.first?.provisioner.github?.privateKeyPath.hasPrefix(home) ?? false)
        XCTAssertTrue(config.runners.first?.preRun?.contains("pre-run") ?? false)
        XCTAssertTrue(config.runners.first?.postRun?.contains("post-run") ?? false)
        XCTAssertEqual(config.runners.first?.healthCheck?.command, "pgrep -f run.sh")
        XCTAssertEqual(config.runners.first?.healthCheck?.interval, 15)
        XCTAssertEqual(config.runners.first?.healthCheck?.delay, 45)
    }

    func testScriptProvisioner() throws {
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
        XCTAssertEqual(config.runners.count, 1)
        XCTAssertNil(config.runners.first?.vm.hardware)
        XCTAssertEqual(config.runners.first?.vm.source.type, .oci)
        XCTAssertEqual(config.runners.first?.vm.source.resolvedSource, "ghcr.io/acme/vm:latest")
        XCTAssertEqual(config.runners.first?.vm.run.noGraphics, true)
        XCTAssertEqual(config.runners.first?.vm.run.noClipboard, false)
        XCTAssertEqual(config.runners.first?.vm.run.nested, false)
        XCTAssertNil(config.runners.first?.vm.run.rootDiskOpts)
        XCTAssertEqual(config.runners.first?.vm.ssh.user, "runner")
        XCTAssertEqual(config.runners.first?.vm.ssh.password, "secret")
        XCTAssertEqual(config.runners.first?.vm.ssh.port, 2222)
        XCTAssertNil(config.runners.first?.vm.ssh.connectMaxRetries)
        XCTAssertEqual(config.runners.first?.provisioner.type, .script)
        XCTAssertTrue(config.runners.first?.provisioner.script?.run.contains("Hello World") ?? false)
        XCTAssertEqual(config.runners.first?.healthCheck?.interval, 30)
        XCTAssertEqual(config.runners.first?.healthCheck?.delay, 60)
    }

    func testExplicitRunnersConfig() throws {
        let yaml = """
        runners:
          - name: runner-a
            vm:
              source:
                type: local
                name: vm-a
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
                name: vm-b
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
        XCTAssertEqual(config.runners.count, 2)
        XCTAssertEqual(config.runners.first?.name, "runner-a")
        XCTAssertEqual(config.runners.first?.vm.source.resolvedSource, "vm-a")
        XCTAssertEqual(config.runners.last?.stopAfter, 2)
        XCTAssertEqual(config.runners.last?.vm.source.resolvedSource, "vm-b")
        XCTAssertEqual(config.runners.first?.healthCheck?.command, "true")
    }

    func testRunnerGroupDecodes() throws {
        let yaml = """
        runners:
          - name: runner-1
            vm:
              source:
                type: oci
                image: ghcr.io/acme/vm:latest
              ssh:
                user: admin
                password: admin
            provisioner:
              type: github
              config:
                appId: 42
                organization: acme
                privateKeyPath: ~/key.pem
                runnerName: runner-1
                runnerGroup: mac-fleet
        """
        let config = try Config.load(path: writeTempFile(contents: yaml).path)
        XCTAssertEqual(config.runners.first?.provisioner.github?.runnerGroup, "mac-fleet")
    }

    func testFixturesLoad() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
        let files = try FileManager.default.contentsOfDirectory(atPath: fixtures.path).filter { $0.hasSuffix(".yml") }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertNoThrow(try Config.load(path: fixtures.appendingPathComponent(file).path), file)
        }
    }
}
