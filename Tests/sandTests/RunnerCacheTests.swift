import CryptoKit
import Foundation
import XCTest
@testable import sand

private final class FakeDownloader: @unchecked Sendable {
    private let lock = NSLock()
    private let payload: Data
    private let delayNanoseconds: UInt64
    private var urls: [URL] = []

    init(payload: Data, delayNanoseconds: UInt64 = 0) {
        self.payload = payload
        self.delayNanoseconds = delayNanoseconds
    }

    var requested: [URL] {
        lock.withLock { urls }
    }

    func download(_ url: URL) async throws -> URL {
        lock.withLock { urls.append(url) }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try payload.write(to: file)
        return file
    }
}

final class RunnerCacheTests: XCTestCase {
    private let payload = Data("runner tarball".utf8)
    private var digest: String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private func makeDirectory() throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url.path
    }

    private func write(_ contents: String, to directory: String, _ name: String) throws {
        try Data(contents.utf8).write(to: URL(fileURLWithPath: (directory as NSString).appendingPathComponent(name)))
    }

    func testPlatformMapping() {
        XCTAssertEqual(RunnerAsset.platform(os: "Darwin", arch: "arm64"), "osx-arm64")
        XCTAssertEqual(RunnerAsset.platform(os: "Linux", arch: "aarch64"), "linux-arm64")
        XCTAssertEqual(RunnerAsset.platform(os: "Linux", arch: "x86_64"), "linux-x64")
        XCTAssertNil(RunnerAsset.platform(os: "FreeBSD", arch: "amd64"))
        XCTAssertEqual(
            RunnerAsset(platform: "osx-arm64", version: "2.331.0").url.absoluteString,
            "https://github.com/actions/runner/releases/download/v2.331.0/actions-runner-osx-arm64-2.331.0.tar.gz"
        )
    }

    func testDownloadsVerifiesAndReusesTarball() async throws {
        let directory = try makeDirectory()
        let downloader = FakeDownloader(payload: payload)
        let cache = RunnerCache(download: downloader.download)
        let asset = RunnerAsset(platform: "osx-arm64", version: "2.331.0")

        let first = try await cache.verifiedTarball(directory: directory, asset: asset, digest: digest)
        let second = try await cache.verifiedTarball(directory: directory, asset: asset, digest: digest)

        XCTAssertEqual(first, (directory as NSString).appendingPathComponent(asset.name))
        XCTAssertEqual(second, first)
        XCTAssertEqual(downloader.requested, [asset.url])
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: first)), payload)
        XCTAssertEqual(try String(contentsOfFile: first + ".sha256", encoding: .utf8), digest)
    }

    func testDigestMismatchLeavesNothingInCache() async throws {
        let directory = try makeDirectory()
        let cache = RunnerCache(download: FakeDownloader(payload: Data("tampered".utf8)).download)
        let asset = RunnerAsset(platform: "osx-arm64", version: "2.331.0")

        do {
            _ = try await cache.verifiedTarball(directory: directory, asset: asset, digest: digest)
            XCTFail("expected digest mismatch")
        } catch RunnerCacheError.digestMismatch {
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory), [])
    }

    func testTamperedCachedTarballIsReplaced() async throws {
        let directory = try makeDirectory()
        let asset = RunnerAsset(platform: "osx-arm64", version: "2.331.0")
        try write("tampered", to: directory, asset.name)
        try write(digest, to: directory, asset.name + ".sha256")
        let downloader = FakeDownloader(payload: payload)

        let path = try await RunnerCache(download: downloader.download).verifiedTarball(directory: directory, asset: asset, digest: digest)

        XCTAssertEqual(downloader.requested.count, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), payload)
    }

    func testConcurrentRequestsShareOneDownload() async throws {
        let directory = try makeDirectory()
        let downloader = FakeDownloader(payload: payload, delayNanoseconds: 100_000_000)
        let cache = RunnerCache(download: downloader.download)
        let asset = RunnerAsset(platform: "osx-arm64", version: "2.331.0")
        let digest = digest

        let paths = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await cache.verifiedTarball(directory: directory, asset: asset, digest: digest) }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        XCTAssertEqual(Set(paths).count, 1)
        XCTAssertEqual(downloader.requested.count, 1)
    }

    func testNewestVerifiedTarballSkipsUnverifiedEntries() throws {
        let directory = try makeDirectory()
        try write("runner tarball", to: directory, "actions-runner-osx-arm64-2.330.0.tar.gz")
        try write(digest, to: directory, "actions-runner-osx-arm64-2.330.0.tar.gz.sha256")
        try write("guest written", to: directory, "actions-runner-osx-arm64-2.331.0.tar.gz")
        try write("runner tarball", to: directory, "actions-runner-osx-arm64-2.332.0.tar.gz")
        try write(digest, to: directory, "actions-runner-osx-arm64-2.332.0.tar.gz.sha256")
        try write("other platform", to: directory, "actions-runner-linux-x64-2.340.0.tar.gz")

        let newest = RunnerCache.newestVerifiedTarball(directory: directory, platform: "osx-arm64")
        XCTAssertEqual(newest?.version, "2.332.0")

        try write("tampered", to: directory, "actions-runner-osx-arm64-2.332.0.tar.gz")
        XCTAssertEqual(RunnerCache.newestVerifiedTarball(directory: directory, platform: "osx-arm64")?.version, "2.330.0")
        XCTAssertNil(RunnerCache.newestVerifiedTarball(directory: directory, platform: "osx-x64"))
    }

    func testPrunesOlderVersionsOfSamePlatform() async throws {
        let directory = try makeDirectory()
        for version in ["2.327.0", "2.328.0", "2.329.0", "2.330.0"] {
            try write("old", to: directory, "actions-runner-osx-arm64-\(version).tar.gz")
            try write("old", to: directory, "actions-runner-osx-arm64-\(version).tar.gz.sha256")
        }
        try write("other", to: directory, "actions-runner-linux-x64-2.300.0.tar.gz")
        let cache = RunnerCache(download: FakeDownloader(payload: payload).download)

        _ = try await cache.verifiedTarball(directory: directory, asset: RunnerAsset(platform: "osx-arm64", version: "2.331.0"), digest: digest)

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory))
        XCTAssertEqual(remaining, [
            "actions-runner-osx-arm64-2.331.0.tar.gz", "actions-runner-osx-arm64-2.331.0.tar.gz.sha256",
            "actions-runner-osx-arm64-2.330.0.tar.gz", "actions-runner-osx-arm64-2.330.0.tar.gz.sha256",
            "actions-runner-osx-arm64-2.329.0.tar.gz", "actions-runner-osx-arm64-2.329.0.tar.gz.sha256",
            "actions-runner-linux-x64-2.300.0.tar.gz"
        ])
    }
}
