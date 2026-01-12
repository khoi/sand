import ArgumentParser
import Foundation

struct Sand: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    mutating func run() async throws {
        let config = try Config.load(path: config)
        let processRunner = SystemProcessRunner()
        let tart = Tart(processRunner: processRunner)
        let auth = try GitHubAuth(appId: config.github.appId, privateKeyPath: config.github.privateKeyPath)
        let github = GitHubService(auth: auth, session: URLSession.shared, organization: config.github.organization, repository: config.github.repository)
        let provisioner = GitHubProvisioner()
        let ssh = SSHExecutor()
        let runner = Runner(tart: tart, github: github, provisioner: provisioner, ssh: ssh, config: config)
        try await runner.run()
    }
}

Sand.main()
