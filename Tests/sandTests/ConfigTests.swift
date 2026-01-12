import XCTest
@testable import sand

final class ConfigTests: XCTestCase {
    func testParsesConfigAndExpandsPaths() throws {
        let yaml = """
        stopAfter: 1
        source: file://~/vm
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
        XCTAssertEqual(config.source, "file://\(FileManager.default.homeDirectoryForCurrentUser.path)/vm")
        XCTAssertEqual(config.provisioner.type, .github)
        XCTAssertEqual(config.provisioner.github?.organization, "acme")
        XCTAssertEqual(config.provisioner.github?.repository, "repo")
        XCTAssertEqual(config.provisioner.github?.extraLabels ?? [], ["fast", "arm64"])
        XCTAssertTrue(config.provisioner.github?.privateKeyPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) ?? false)
    }

    func testOptionalFields() throws {
        let yaml = """
        source: ghcr.io/acme/vm:latest
        provisioner:
          type: github
          config:
            appId: 1
            organization: acme
            privateKeyPath: /tmp/key.pem
            runnerName: runner-1
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertNil(config.stopAfter)
        XCTAssertNil(config.provisioner.github?.repository)
        XCTAssertNil(config.provisioner.github?.extraLabels)
    }

    func testScriptProvisioner() throws {
        let yaml = """
        stopAfter: 3
        source: ghcr.io/acme/vm:latest
        provisioner:
          type: script
          config:
            run: |
              echo "Hello World"
              sleep 1
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertEqual(config.stopAfter, 3)
        XCTAssertEqual(config.provisioner.type, .script)
        XCTAssertEqual(config.provisioner.script?.run.contains("Hello World"), true)
    }
}
