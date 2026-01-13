import ArgumentParser
import Darwin
import Foundation
import Logging

@main
@available(macOS 14.0, *)
struct Sand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Run.self, Doctor.self, Validate.self]
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
        var cleanupTargets: [(VMShutdownCoordinator, Tart)] = []
        if let runnerConfigs = config.runners, !runnerConfigs.isEmpty {
            for (index, runnerConfig) in runnerConfigs.enumerated() {
                let runnerIndex = index + 1
                let tart = Tart(processRunner: processRunner)
                let shutdownLogger = Logger(label: "sand.shutdown.\(runnerIndex)")
                let shutdownCoordinator = VMShutdownCoordinator(logger: shutdownLogger)
                cleanupTargets.append((shutdownCoordinator, tart))
                let runnerName = runnerConfig.name
                let github = try githubService(for: runnerConfig.provisioner)
                let runnerWrapper = Config(
                    vm: runnerConfig.vm,
                    provisioner: runnerConfig.provisioner,
                    stopAfter: runnerConfig.stopAfter,
                    runnerCount: nil,
                    healthCheck: runnerConfig.healthCheck
                )
                let runner = Runner(
                    tart: tart,
                    github: github,
                    provisioner: provisioner,
                    config: runnerWrapper,
                    shutdownCoordinator: shutdownCoordinator,
                    vmName: runnerName,
                    logLabel: runnerName.isEmpty ? "runner\(runnerIndex)" : runnerName
                )
                runners.append(runner)
            }
        } else {
            let runnerCount = config.runnerCount ?? 1
            let github = try githubService(for: config.provisioner)
            for index in 1...runnerCount {
                let tart = Tart(processRunner: processRunner)
                let shutdownLogger = Logger(label: "sand.shutdown.\(index)")
                let shutdownCoordinator = VMShutdownCoordinator(logger: shutdownLogger)
                cleanupTargets.append((shutdownCoordinator, tart))
                let runnerConfig = configForRunner(config, index: index, total: runnerCount)
                let vmName = runnerCount == 1 ? "sandrunner" : "sandrunner-\(index)"
                let runner = Runner(
                    tart: tart,
                    github: github,
                    provisioner: provisioner,
                    config: runnerConfig,
                    shutdownCoordinator: shutdownCoordinator,
                    vmName: vmName,
                    logLabel: "runner\(index)"
                )
                runners.append(runner)
            }
        }
        let shutdownLogger = Logger(label: "sand.shutdown")
        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM], logger: shutdownLogger) {
            for (coordinator, tart) in cleanupTargets {
                coordinator.cleanup(tart: tart)
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

    private func configForRunner(_ config: Config, index: Int, total: Int) -> Config {
        guard total > 1 else {
            return config
        }
        switch config.provisioner?.type {
        case .script:
            return config
        case .github:
            guard let github = config.provisioner?.github else {
                return config
            }
            let runnerName = "\(github.runnerName)-\(index)"
            let updatedGitHub = GitHubProvisionerConfig(
                appId: github.appId,
                organization: github.organization,
                repository: github.repository,
                privateKeyPath: github.privateKeyPath,
                runnerName: runnerName,
                extraLabels: github.extraLabels
            )
            let updatedProvisioner = Config.Provisioner(type: .github, script: nil, github: updatedGitHub)
            return Config(
                vm: config.vm,
                provisioner: updatedProvisioner,
                stopAfter: config.stopAfter,
                runnerCount: config.runnerCount,
                healthCheck: config.healthCheck
            )
        default:
            return config
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
