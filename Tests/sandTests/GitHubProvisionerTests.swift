import Foundation
import XCTest
@testable import sand

final class GitHubProvisionerTests: XCTestCase {
    private func config(
        repository: String? = nil,
        extraLabels: [String]? = nil,
        runnerGroup: String? = nil
    ) -> GitHubProvisionerConfig {
        GitHubProvisionerConfig(
            appId: 1,
            organization: "org",
            repository: repository,
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: extraLabels,
            runnerGroup: runnerGroup
        )
    }

    func testScriptExtractsCopiedTarballAndRegisters() {
        let script = GitHubProvisioner().script(config: config(repository: "repo"), runnerName: "runner-1-0a1b2", runnerToken: "token")
        XCTAssertEqual(script, [
            "rm -rf ~/actions-runner && mkdir ~/actions-runner",
            "tar xzf ~/actions-runner.tar.gz -C ~/actions-runner",
            "echo \"Runner extracted\"",
            "~/actions-runner/config.sh --url https://github.com/org/repo --name runner-1-0a1b2 --token token --ephemeral --unattended --replace --labels sand",
            "echo \"Runner configured, starting ~/actions-runner/run.sh\"",
            "~/actions-runner/run.sh"
        ])
    }

    func testScriptNeverDownloadsInGuest() {
        let joined = GitHubProvisioner().script(config: config(), runnerName: "runner-1", runnerToken: "token").joined(separator: "\n")
        XCTAssertFalse(joined.contains("curl"))
        XCTAssertTrue(joined.contains("--url https://github.com/org --name"))
    }

    func testScriptWithExtraLabels() {
        let joined = GitHubProvisioner().script(config: config(extraLabels: ["fast", "arm64"]), runnerName: "runner-1", runnerToken: "token").joined(separator: "\n")
        XCTAssertTrue(joined.contains("--labels sand,fast,arm64"))
    }

    func testScriptRegistersIntoQuotedRunnerGroup() {
        let joined = GitHubProvisioner().script(config: config(runnerGroup: "Mac Fleet's"), runnerName: "runner-1", runnerToken: "token").joined(separator: "\n")
        XCTAssertTrue(joined.contains("--labels sand --runnergroup 'Mac Fleet'\\''s'"))
    }

    func testScriptOmitsRunnerGroupByDefault() {
        let joined = GitHubProvisioner().script(config: config(), runnerName: "runner-1", runnerToken: "token").joined(separator: "\n")
        XCTAssertFalse(joined.contains("--runnergroup"))
    }

    func testUniqueRunnerNameAppendsHexSuffix() {
        let name = GitHubProvisioner.uniqueRunnerName(base: "runner-1")
        XCTAssertNotNil(name.wholeMatch(of: /runner-1-[0-9a-f]{5}/))
    }
}
