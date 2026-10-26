import Foundation
import Testing
@testable import sand

struct AdditionalDisksTests {
    private func load(disks: String = "") throws -> Config {
        let file = try writeTempFile(contents: """
        runners:
          - name: example
            vm:
              source: {type: local, name: base}
              \(disks)
            provisioner:
              type: script
              config: {run: 'true'}
        """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        return try Config.load(path: file.path)
    }

    @Test func omittedDisksPreserveExistingBehavior() throws {
        let config = try load()
        #expect(config.runners[0].vm.additionalDisks.isEmpty)
        let process = MockProcessRunner()
        try makeTart(process).run(name: "example")
        #expect(process.startCalls[0].arguments == ["run", "example", "--no-graphics"])
    }

    @Test func expandsTildeWithoutChangingAttachmentOptions() throws {
        let config = try load(disks: "additionalDisks: ['~/cache disk.raw:ro', 'nbd://localhost:10809/cache:sync=full']")
        #expect(config.runners[0].vm.additionalDisks == [
            Config.expandPath("~/cache disk.raw:ro"),
            "nbd://localhost:10809/cache:sync=full"
        ])
    }

    @Test(arguments: ["", " ", "\t"])
    func rejectsEmptyDiskEntries(value: String) throws {
        let encoded = String(data: try JSONEncoder().encode([value]), encoding: .utf8)!
        let issues = ConfigValidator().validate(try load(disks: "additionalDisks: \(encoded)"))
        #expect(issues.contains { $0.message.contains("vm.additionalDisks entries must not be empty") })
    }

    @Test func leavesDiskSyntaxAndExistenceValidationToTart() throws {
        let config = try load(disks: "additionalDisks: ['/path/not/yet/present.raw', 'nbd://localhost:10809/cache:sync=full']")
        #expect(ConfigValidator().validate(config).isEmpty)
    }

    @Test func forwardsAttachmentsAsOpaqueArgumentsAlongsideManagedOptions() throws {
        let process = MockProcessRunner()
        var options = Tart.RunOptions.default
        options.rootDiskOpts = "caching=cached"
        options.additionalDisks = [
            "/tmp/cache disk.raw:sync=full",
            "/tmp/$(not-a-command).img:ro",
            "--no-graphics"
        ]
        try makeTart(process).run(name: "example", options: options)
        #expect(process.startCalls[0].arguments == [
            "run", "example", "--no-graphics", "--root-disk-opts=caching=cached",
            "--disk=/tmp/cache disk.raw:sync=full",
            "--disk=/tmp/$(not-a-command).img:ro",
            "--disk=--no-graphics"
        ])
    }
}
