import ArgumentParser
import Foundation

@main
@available(macOS 14.0, *)
struct Sand: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    mutating func run() async throws {
        let config = try Config.load(path: config)
        let processRunner = SystemProcessRunner()
        let tart = Tart(processRunner: processRunner)
        let github: GitHubService?
        switch config.provisioner.type {
        case .github:
            guard let githubConfig = config.provisioner.github else {
                github = nil
                break
            }
            let auth = try GitHubAuth(appId: githubConfig.appId, privateKeyPath: githubConfig.privateKeyPath)
            github = GitHubService(auth: auth, session: URLSession.shared, organization: githubConfig.organization, repository: githubConfig.repository)
        case .script:
            github = nil
        }
        let provisioner = GitHubProvisioner()
        let ssh = SSHExecutor()
        let runner = Runner(tart: tart, github: github, provisioner: provisioner, ssh: ssh, config: config)
        try await runner.run()
    }
}
