import XCTest
@testable import sand

final class ConfigTests: XCTestCase {
    func testParsesConfigAndExpandsPaths() throws {
        let yaml = """
        stopAfter: 1
        vm:
          source:
            type: local
            path: ~/vm
          hardware:
            ramGb: 4
          mounts:
            - hostPath: ~/cache
              guestFolder: cache
              readOnly: true
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
        XCTAssertEqual(config.stopAfter, 1)
        XCTAssertEqual(config.vm.hardware?.ramGb, 4)
        XCTAssertEqual(config.vm.source.type, .local)
        XCTAssertEqual(
            config.vm.source.resolvedSource,
            "file://\(FileManager.default.homeDirectoryForCurrentUser.path)/vm"
        )
        XCTAssertEqual(config.vm.mounts.first?.hostPath, "\(FileManager.default.homeDirectoryForCurrentUser.path)/cache")
        XCTAssertEqual(config.vm.mounts.first?.guestFolder, "cache")
        XCTAssertEqual(config.vm.mounts.first?.readOnly, true)
        XCTAssertEqual(config.provisioner.type, .github)
        XCTAssertEqual(config.provisioner.github?.organization, "acme")
        XCTAssertEqual(config.provisioner.github?.repository, "repo")
        XCTAssertEqual(config.provisioner.github?.extraLabels ?? [], ["fast", "arm64"])
        XCTAssertTrue(config.provisioner.github?.privateKeyPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) ?? false)
    }

    func testScriptProvisioner() throws {
        let yaml = """
        vm:
          source:
            type: oci
            image: ghcr.io/acme/vm:latest
        provisioner:
          type: script
          config:
            run: |
              echo "Hello World"
              sleep 1
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertNil(config.vm.hardware)
        XCTAssertEqual(config.vm.source.type, .oci)
        XCTAssertEqual(config.vm.source.resolvedSource, "ghcr.io/acme/vm:latest")
        XCTAssertEqual(config.provisioner.type, .script)
        XCTAssertEqual(config.provisioner.script?.run.contains("Hello World"), true)
    }
}
