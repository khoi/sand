import XCTest
@testable import sand

final class GitHubProvisionerTests: XCTestCase {
    func testScriptWithExtraLabels() {
        let provisioner = GitHubProvisioner()
        let config = Config.Provisioner.GitHub(
            appId: 1,
            organization: "org",
            repository: "repo",
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: ["fast", "arm64"]
        )
        let script = provisioner.script(config: config, runnerToken: "token", downloadURL: URL(string: "https://example.com/runner.tar.gz")!)
        XCTAssertTrue(script.contains("--labels sand,fast,arm64"))
        XCTAssertTrue(script.contains("--url https://github.com/org/repo"))
    }

    func testScriptWithDefaultLabels() {
        let provisioner = GitHubProvisioner()
        let config = Config.Provisioner.GitHub(
            appId: 1,
            organization: "org",
            repository: nil,
            privateKeyPath: "/tmp/key.pem",
            runnerName: "runner-1",
            extraLabels: nil
        )
        let script = provisioner.script(config: config, runnerToken: "token", downloadURL: URL(string: "https://example.com/runner.tar.gz")!)
        XCTAssertTrue(script.contains("--labels sand"))
        XCTAssertTrue(script.contains("--url https://github.com/org"))
    }
}
