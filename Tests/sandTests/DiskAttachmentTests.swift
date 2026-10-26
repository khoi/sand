import Foundation
import Testing
@testable import sand

struct DiskAttachmentTests {
    private func decode(_ entry: String) throws -> DiskAttachment {
        let file = try writeTempFile(contents: """
        runners:
          - name: example
            vm:
              source: {type: local, name: base}
              additionalDisks: [\(entry)]
            provisioner:
              type: script
              config: {run: 'true'}
        """)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        return try #require(Config.load(path: file.path).runners[0].vm.additionalDisks.first)
    }

    @Test func mappingDecodesTypedOptionsAndCanonicalArgument() throws {
        let disk = try decode(#"{"source":"/tmp/cache disk.raw","readOnly":true,"synchronization":"full","caching":"uncached"}"#)
        #expect(disk.source == "/tmp/cache disk.raw")
        #expect(disk.readOnly)
        #expect(disk.synchronization == .full)
        #expect(disk.caching == .uncached)
        #expect(disk.tartArgument == "--disk=/tmp/cache disk.raw:ro,sync=full,caching=uncached")
    }

    @Test(arguments: ["/tmp/cache disk.raw", "/tmp/cache:backup", "ghcr.io/acme/image:16.0",
                      "ghcr.io:443/acme/image:16.0", "nbd://localhost:10809/cache",
                      "nbds+unix:///tmp/nbd.sock/cache"])
    func scalarPlainSourcesPreserveColonsAndDefaults(source: String) throws {
        let scalar = String(data: try JSONEncoder().encode(source), encoding: .utf8)!
        let disk = try decode(scalar)
        #expect(disk.source == source)
        #expect(!disk.readOnly && disk.synchronization == nil && disk.caching == nil)
        #expect(disk.tartArgument == "--disk=\(source)")
    }

    @Test(arguments: DiskAttachment.Synchronization.allCases, DiskAttachment.Caching.allCases)
    func allDiskImageOptionValuesFormatExactly(sync: DiskAttachment.Synchronization,
                                              caching: DiskAttachment.Caching) throws {
        let disk = try decode("{source: /tmp/cache.raw, synchronization: \(sync.rawValue), caching: \(caching.rawValue)}")
        #expect(disk.synchronization == sync && disk.caching == caching)
        #expect(disk.tartArgument == "--disk=/tmp/cache.raw:sync=\(sync.rawValue),caching=\(caching.rawValue)")
    }

    @Test(arguments: [
        #""/tmp/cache.raw:ro""#,
        #""/tmp/cache.raw:sync=full""#,
        #"{}"#,
        #"{"source":""}"#,
        #"{"source":"/tmp/cache.raw","synchronization":"fast"}"#,
        #"{"source":"/tmp/cache.raw","caching":"fast"}"#,
        #"{"source":"/tmp/cache.raw","readOnly":"maybe"}"#,
        #"{"source":"/tmp/cache.raw","arguments":["--no-graphics"]}"#,
        #"{"path":"/tmp/cache.raw"}"#,
        #"{"source":"nbd://localhost:10809/cache","synchronization":"fsync"}"#,
        #"{"source":"nbd://localhost:10809/cache","caching":"cached"}"#
    ])
    func rejectsInvalidSchemaOptionsAndInlineOptionStrings(entry: String) {
        #expect(throws: (any Error).self) { _ = try decode(entry) }
    }

    @Test(arguments: ["", " ", "\t", "cache\n.raw", "cache\0.raw", "cache:"])
    func programmaticConstructionCannotBypassSourceValidation(source: String) {
        #expect(throws: DiskAttachment.InvalidAttachment.self) { _ = try DiskAttachment(source: source) }
    }

    @Test func expansionRetainsOptionsAndDoesNotRewriteURLs() throws {
        let local = try DiskAttachment(source: "~/cache.raw", readOnly: true, synchronization: .full).expanded()
        #expect(local.source == Config.expandPath("~/cache.raw"))
        #expect(local.readOnly && local.synchronization == .full)
        let network = try DiskAttachment(source: "nbd://localhost:10809/cache", synchronization: .disabled)
        #expect(network.expanded() == network)
        #expect(network.tartArgument == "--disk=nbd://localhost:10809/cache:sync=none")
    }
}
