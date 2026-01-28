import Foundation
import XCTest
@testable import sand

final class GitHubRunnerVersionResolverTests: XCTestCase {
    func testParseTagName() {
        XCTAssertEqual(GitHubRunnerVersionResolver.parseTagName("v2.331.0"), "2.331.0")
        XCTAssertEqual(GitHubRunnerVersionResolver.parseTagName("2.331.0"), "2.331.0")
        XCTAssertNil(GitHubRunnerVersionResolver.parseTagName("v2.331.0-beta"))
        XCTAssertNil(GitHubRunnerVersionResolver.parseTagName("v"))
        XCTAssertNil(GitHubRunnerVersionResolver.parseTagName(""))
    }

    func testNewestCachedVersionSelectsHighest() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        let filenames = [
            "actions-runner-osx-arm64-2.330.0.tar.gz",
            "actions-runner-osx-arm64-2.331.0.tar.gz",
            "actions-runner-linux-x64-2.329.1.tar.gz",
            "notes.txt"
        ]
        for name in filenames {
            let url = tempDir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }

        let newest = GitHubRunnerVersionResolver.newestCachedVersion(in: tempDir.path)
        XCTAssertEqual(newest, "2.331.0")
    }

    func testNewestCachedVersionReturnsNilForEmptyDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let newest = GitHubRunnerVersionResolver.newestCachedVersion(in: tempDir.path)
        XCTAssertNil(newest)
    }
}
