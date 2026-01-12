import Foundation
import Testing
@testable import sand

@Test
func scriptWithExtraLabels() {
    let provisioner = GitHubProvisioner()
    let config = GitHubProvisionerConfig(
        appId: 1,
        organization: "org",
        repository: "repo",
        privateKeyPath: "/tmp/key.pem",
        runnerName: "runner-1",
        extraLabels: ["fast", "arm64"]
    )
    let script = provisioner.script(
        config: config,
        runnerToken: "token",
        downloadURL: URL(string: "https://example.com/runner.tar.gz")!
    )
    #expect(script.contains("--labels sand,fast,arm64"))
    #expect(script.contains("--url https://github.com/org/repo"))
}

@Test
func scriptWithDefaultLabels() {
    let provisioner = GitHubProvisioner()
    let config = GitHubProvisionerConfig(
        appId: 1,
        organization: "org",
        repository: nil,
        privateKeyPath: "/tmp/key.pem",
        runnerName: "runner-1",
        extraLabels: nil
    )
    let script = provisioner.script(
        config: config,
        runnerToken: "token",
        downloadURL: URL(string: "https://example.com/runner.tar.gz")!
    )
    #expect(script.contains("--labels sand"))
    #expect(script.contains("--url https://github.com/org"))
}
