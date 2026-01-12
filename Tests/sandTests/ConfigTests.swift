import XCTest
@testable import sand

final class ConfigTests: XCTestCase {
    func testParsesConfigAndExpandsPaths() throws {
        let yaml = """
        source: file://~/vm
        github:
          appId: 42
          organization: acme
          repository: repo
          privateKeyPath: ~/key.pem
          runnerName: runner-1
          extraLabels: [fast, arm64]
        ssh:
          username: admin
          password: admin
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertEqual(config.source, "file://\(FileManager.default.homeDirectoryForCurrentUser.path)/vm")
        XCTAssertEqual(config.github.organization, "acme")
        XCTAssertEqual(config.github.repository, "repo")
        XCTAssertEqual(config.github.extraLabels ?? [], ["fast", "arm64"])
        XCTAssertTrue(config.github.privateKeyPath.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path))
    }

    func testOptionalFields() throws {
        let yaml = """
        source: ghcr.io/acme/vm:latest
        github:
          appId: 1
          organization: acme
          privateKeyPath: /tmp/key.pem
          runnerName: runner-1
        ssh:
          username: admin
          password: admin
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertNil(config.github.repository)
        XCTAssertNil(config.github.extraLabels)
    }
}
