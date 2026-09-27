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

    func testParseReleaseCollectsAssetDigests() throws {
        let digest = String(repeating: "ab", count: 32)
        let json = """
        {
          "tag_name": "v2.331.0",
          "assets": [
            {"name": "actions-runner-osx-arm64-2.331.0.tar.gz", "digest": "sha256:\(digest.uppercased())"},
            {"name": "actions-runner-linux-x64-2.331.0.tar.gz", "digest": null},
            {"name": "actions-runner-linux-arm64-2.331.0.tar.gz", "digest": "md5:abc"}
          ]
        }
        """
        let release = try GitHubRunnerVersionResolver.parseRelease(Data(json.utf8))
        XCTAssertEqual(release, RunnerRelease(version: "2.331.0", digests: ["actions-runner-osx-arm64-2.331.0.tar.gz": digest]))
    }

    func testParseDigestRejectsMalformedValues() {
        XCTAssertNil(GitHubRunnerVersionResolver.parseDigest("sha256:xyz"))
        XCTAssertNil(GitHubRunnerVersionResolver.parseDigest("sha256:abcd"))
        XCTAssertNil(GitHubRunnerVersionResolver.parseDigest(String(repeating: "a", count: 64)))
    }

    func testIsNewerComparesNumerically() {
        XCTAssertTrue(GitHubRunnerVersionResolver.isNewer("2.331.0", than: "2.330.9"))
        XCTAssertTrue(GitHubRunnerVersionResolver.isNewer("2.331.10", than: "2.331.9"))
        XCTAssertFalse(GitHubRunnerVersionResolver.isNewer("2.331.0", than: "2.331.0"))
        XCTAssertFalse(GitHubRunnerVersionResolver.isNewer("2.330.0", than: "2.331"))
    }
}
