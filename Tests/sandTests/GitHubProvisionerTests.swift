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
    let script = provisioner.script(config: config, runnerToken: "token")
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("--labels sand,fast,arm64"))
    #expect(joined.contains("--url https://github.com/org/repo"))
    #expect(joined.contains("actions/runner/releases/download"))
    #expect(!joined.contains("runner cache"))
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
    let script = provisioner.script(config: config, runnerToken: "token")
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("--labels sand"))
    #expect(joined.contains("--url https://github.com/org"))
    #expect(joined.contains("actions-runner-${runner_os}-${runner_arch}"))
    #expect(!joined.contains("runner cache"))
}

@Test
func scriptIncludesRunnerCacheLogic() {
    let provisioner = GitHubProvisioner()
    let config = GitHubProvisionerConfig(
        appId: 1,
        organization: "org",
        repository: "repo",
        privateKeyPath: "/tmp/key.pem",
        runnerName: "runner-1",
        extraLabels: nil
    )
    let script = provisioner.script(config: config, runnerToken: "token", cacheDirectory: "sand-cache")
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("runner cache hit"))
    #expect(joined.contains("runner cache miss"))
    #expect(joined.contains("runner cache unavailable"))
    #expect(joined.contains("cache_dir="))
    #expect(joined.contains("cache_file="))
}

@Test
func scriptUsesRunnerCacheDirectoryValue() {
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
    let script = provisioner.script(config: config, runnerToken: "token", cacheDirectory: cacheDirectory)
    let joined = script.joined(separator: "\n")
    #expect(joined.contains("cache_dir_name=\"\(cacheDirectory)\""))
}
