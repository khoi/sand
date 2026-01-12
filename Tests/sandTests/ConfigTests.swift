import XCTest
@testable import sand

final class ConfigTests: XCTestCase {
    func testParsesConfigAndExpandsPaths() throws {
        let yaml = """
        vm:
          source:
            type: local
            path: ~/vm
          hardware:
            ramGb: 4
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertEqual(config.vm.hardware?.ramGb, 4)
        XCTAssertEqual(config.vm.source.type, .local)
        XCTAssertEqual(
            config.vm.source.resolvedSource,
            "file://\(FileManager.default.homeDirectoryForCurrentUser.path)/vm"
        )
    }

    func testOptionalFields() throws {
        let yaml = """
        vm:
          source:
            type: oci
            image: ghcr.io/acme/vm:latest
        """
        let url = try writeTempFile(contents: yaml)
        let config = try Config.load(path: url.path)
        XCTAssertNil(config.vm.hardware)
        XCTAssertEqual(config.vm.source.type, .oci)
        XCTAssertEqual(config.vm.source.resolvedSource, "ghcr.io/acme/vm:latest")
    }
}
