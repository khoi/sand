import ArgumentParser
import Darwin
import Foundation
import Logging

@main
@available(macOS 14.0, *)
struct Sand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Run.self, Destroy.self, Doctor.self, Validate.self]
    )
}

@available(macOS 14.0, *)
struct Run: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = "sand.yml"

    mutating func run() async throws {
        LoggingSystem.bootstrap { label in
            StreamLogHandler.standardOutput(label: label)
        }
        let logger = Logger(label: "sand")
        let missing = DependencyChecker.missingCommands(["tart", "sshpass", "ssh"])
        if !missing.isEmpty {
            throw ValidationError("Missing required dependencies in PATH: \(missing.joined(separator: ", ")). Install them and re-run.")
        }
        let config = try Config.load(path: config)
        let validator = ConfigValidator()
        let issues = validator.validate(config)
        let errors = issues.filter { $0.severity == .error }
        if !errors.isEmpty {
            let message = errors.map(\.message).joined(separator: " ")
            throw ValidationError("Config validation failed: \(message)")
        }
        for warning in issues where warning.severity == .warning {
            logger.warning("\(warning.message)")
        }
        let processRunner = SystemProcessRunner()
        let provisioner = GitHubProvisioner()
        var runners: [Runner] = []
        var cleanupTargets: [VMShutdownCoordinator] = []
        for (index, runnerConfig) in config.runners.enumerated() {
            let runnerIndex = index + 1
            let tart = Tart(processRunner: processRunner)
            let shutdownLogger = Logger(label: "sand.shutdown.\(runnerIndex)")
            let destroyer = VMDestroyer(tart: tart, logger: shutdownLogger)
            let shutdownCoordinator = VMShutdownCoordinator(destroyer: destroyer)
            cleanupTargets.append(shutdownCoordinator)
            let runnerName = runnerConfig.name
            let github = try githubService(for: runnerConfig.provisioner)
            let runner = Runner(
                tart: tart,
                github: github,
                provisioner: provisioner,
                config: runnerConfig,
                shutdownCoordinator: shutdownCoordinator,
                vmName: runnerName,
                logLabel: runnerName.isEmpty ? "runner\(runnerIndex)" : runnerName
            )
            runners.append(runner)
        }
        let shutdownLogger = Logger(label: "sand.shutdown")
        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM], logger: shutdownLogger) {
            for coordinator in cleanupTargets {
                coordinator.cleanup()
            }
        }
        defer {
            _ = signalHandler
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for runner in runners {
                group.addTask {
                    try await runner.run()
                }
            }
            try await group.waitForAll()
        }
    }

    private func githubService(for provisioner: Config.Provisioner?) throws -> GitHubService? {
        guard let provisioner, provisioner.type == .github, let githubConfig = provisioner.github else {
            return nil
        }
        let auth = try GitHubAuth(appId: githubConfig.appId, privateKeyPath: githubConfig.privateKeyPath)
        return GitHubService(
            auth: auth,
            session: URLSession.shared,
            organization: githubConfig.organization,
            repository: githubConfig.repository
        )
    }
}
