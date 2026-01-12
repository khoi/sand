import ArgumentParser
import Darwin
import Foundation
import Logging

@main
@available(macOS 14.0, *)
struct Sand: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    mutating func run() async throws {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
        let config = try Config.load(path: config)
        let processRunner = SystemProcessRunner()
        let tart = Tart(processRunner: processRunner)
        let shutdownLogger = Logger(label: "sand.shutdown")
        let shutdownCoordinator = VMShutdownCoordinator(logger: shutdownLogger)
        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM], logger: shutdownLogger) {
            shutdownCoordinator.cleanup(tart: tart)
        }
        defer {
            _ = signalHandler
        }
        let github: GitHubService?
        switch config.provisioner.type {
        case .github:
            guard let githubConfig = config.provisioner.github else {
                github = nil
                break
            }
            let auth = try GitHubAuth(appId: githubConfig.appId, privateKeyPath: githubConfig.privateKeyPath)
            github = GitHubService(
                auth: auth,
                session: URLSession.shared,
                organization: githubConfig.organization,
                repository: githubConfig.repository
            )
        case .script:
            github = nil
        }
        let provisioner = GitHubProvisioner()
        let runner = Runner(
            tart: tart,
            github: github,
            provisioner: provisioner,
            config: config,
            shutdownCoordinator: shutdownCoordinator
        )
        try await runner.run()
    }
}
