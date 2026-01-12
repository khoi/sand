import ArgumentParser
import Foundation

@main
@available(macOS 14.0, *)
struct Sand: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    @Flag(name: .long, help: "Enable verbose OSLog output (sets OS_LOG_LEVEL=debug, OS_ACTIVITY_MODE=debug, OS_ACTIVITY_DT_MODE=1).")
    var oslogDebug: Bool = false

    mutating func run() async throws {
        if oslogDebug {
            setenv("OS_LOG_LEVEL", "debug", 1)
            setenv("OS_ACTIVITY_MODE", "debug", 1)
            setenv("OS_ACTIVITY_DT_MODE", "1", 1)
        }
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
        let runner = Runner(tart: tart, github: github, provisioner: provisioner, config: config)
        try await runner.run()
    }
}
