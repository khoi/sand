import Foundation
import Testing
@testable import sand

@Test
func runScriptWithExtraLabels() {
    let provisioner = GitHubProvisioner()
    let config = GitHubProvisionerConfig(
        appId: 1,
        organization: "org",
        repository: "repo",
        privateKeyPath: "/tmp/key.pem",
        runnerName: "runner-1",
        extraLabels: ["fast", "arm64"]
    )
    let script = provisioner.runScript(config: config, runnerToken: "token")
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("--labels sand,fast,arm64"))
    #expect(joined.contains("--url https://github.com/org/repo"))
    #expect(!joined.contains("actions/runner/releases/download"))
}

@Test
func runScriptWithDefaultLabels() {
    let provisioner = GitHubProvisioner()
    let config = GitHubProvisionerConfig(
        appId: 1,
        organization: "org",
        repository: nil,
        privateKeyPath: "/tmp/key.pem",
        runnerName: "runner-1",
        extraLabels: nil
    )
    let script = provisioner.runScript(config: config, runnerToken: "token")
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("--labels sand"))
    #expect(joined.contains("--url https://github.com/org"))
    #expect(!joined.contains("actions-runner-${runner_os}-${runner_arch}"))
}

@Test
func installScriptDownloadsRunner() {
    let provisioner = GitHubProvisioner()
    let script = provisioner.installScript()
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("actions/runner/releases/download"))
    #expect(joined.contains("actions-runner-${runner_os}-${runner_arch}"))
    #expect(joined.contains("tar xzf ./actions-runner.tar.gz"))
}
