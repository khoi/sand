import Foundation
import XCTest
@testable import sand

final class GitHubProvisionerTests: XCTestCase {
    func testScriptWithExtraLabels() {
        let provisioner = GitHubProvisioner()
        let config = GitHubProvisionerConfig(
            appId: 1,
            organization: "org",
            repository: "repo",
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: ["fast", "arm64"]
        )
        let runnerVersion = "2.999.0"
        let script = provisioner.script(
            config: config,
            runnerToken: "token",
            runnerVersion: runnerVersion
        )
        let joined = script.joined(separator: "\n")
        XCTAssertTrue(joined.contains("--labels sand,fast,arm64"))
        XCTAssertTrue(joined.contains("--url https://github.com/org/repo"))
        XCTAssertTrue(joined.contains("actions/runner/releases/download"))
        XCTAssertTrue(joined.contains("version=\"\(runnerVersion)\""))
        XCTAssertFalse(joined.contains("runner cache"))
    }

    func testScriptWithDefaultLabels() {
        let provisioner = GitHubProvisioner()
        let config = GitHubProvisionerConfig(
            appId: 1,
            organization: "org",
            repository: nil,
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: nil
        )
        let runnerVersion = "2.999.0"
        let script = provisioner.script(
            config: config,
            runnerToken: "token",
            runnerVersion: runnerVersion
        )
        let joined = script.joined(separator: "\n")
        XCTAssertTrue(joined.contains("--labels sand"))
        XCTAssertTrue(joined.contains("--url https://github.com/org"))
        XCTAssertTrue(joined.contains("actions-runner-${runner_os}-${runner_arch}"))
        XCTAssertTrue(joined.contains("version=\"\(runnerVersion)\""))
        XCTAssertFalse(joined.contains("runner cache"))
    }

    func testScriptIncludesRunnerCacheLogic() {
        let provisioner = GitHubProvisioner()
        let config = GitHubProvisionerConfig(
            appId: 1,
            organization: "org",
            repository: "repo",
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: nil
        )
        let runnerVersion = "2.999.0"
        let script = provisioner.script(
            config: config,
            runnerToken: "token",
            runnerVersion: runnerVersion,
            cacheDirectory: "sand-cache"
        )
        let joined = script.joined(separator: "\n")
        XCTAssertTrue(joined.contains("runner cache hit"))
        XCTAssertTrue(joined.contains("runner cache miss"))
        XCTAssertTrue(joined.contains("runner cache unavailable"))
        XCTAssertTrue(joined.contains("cache_dir="))
        XCTAssertTrue(joined.contains("cache_file="))
        XCTAssertTrue(joined.contains("version=\"\(runnerVersion)\""))
    }

    func testScriptUsesRunnerCacheDirectoryValue() {
        let provisioner = GitHubProvisioner()
        let config = GitHubProvisionerConfig(
            appId: 1,
            organization: "org",
            repository: "repo",
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: nil
        )
        let cacheDirectory = "/var/tmp/runner-cache"
        let runnerVersion = "2.999.0"
        let script = provisioner.script(
            config: config,
            runnerToken: "token",
            runnerVersion: runnerVersion,
            cacheDirectory: cacheDirectory
        )
        let joined = script.joined(separator: "\n")
        XCTAssertTrue(joined.contains("cache_dir_name=\"\(cacheDirectory)\""))
        XCTAssertTrue(joined.contains("version=\"\(runnerVersion)\""))
    }
}
