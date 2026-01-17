import ArgumentParser
import Darwin
import Foundation

@main
@available(macOS 15.0, *)
struct Sand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        subcommands: [Run.self, Destroy.self, Doctor.self, Validate.self]
    )
}

@available(macOS 15.0, *)
struct Run: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var config: String = Config.defaultPath
    @OptionGroup
    var logLevel: LogLevelOptions
    @Flag(name: .long, help: "Validate configuration and prepare VM images without booting.")
    var dryRun: Bool = false

    mutating func run() async throws {
        let level = logLevel.resolvedLevel()
        let logSink = try logLevel.makeLogFileSink()
        let logger = Logger(label: "sand", minimumLevel: level, sink: logSink)
        let requiredDependencies = dryRun ? ["tart"] : ["tart", "sshpass", "ssh"]
        let missing = DependencyChecker.missingCommands(requiredDependencies)
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
        if dryRun {
            for (index, runnerConfig) in config.runners.enumerated() {
                let runnerIndex = index + 1
                let runnerName = runnerConfig.name
                let logLabel = runnerName.isEmpty ? "runner\(runnerIndex)" : runnerName
                let tart = Tart(processRunner: processRunner, logger: Logger(label: "tart.\(logLabel)", minimumLevel: level, sink: logSink))
                let source = runnerConfig.vm.source.resolvedSource
                logger.info("dry-run: prepare source \(source) for \(logLabel)")
                try tart.prepare(source: source)
            }
            logger.info("dry-run complete")
            return
        }

        let provisioner = GitHubProvisioner()
        var runners: [Runner] = []
        var cleanupTargets: [VMShutdownCoordinator] = []
        var runnerControls: [RunnerControl] = []
        for (index, runnerConfig) in config.runners.enumerated() {
            let runnerIndex = index + 1
            let runnerName = runnerConfig.name
            let logLabel = runnerName.isEmpty ? "runner\(runnerIndex)" : runnerName
            let tart = Tart(processRunner: processRunner, logger: Logger(label: "tart.\(logLabel)", minimumLevel: level, sink: logSink))
            let shutdownLogger = Logger(label: "sand.shutdown.\(runnerIndex)", minimumLevel: level, sink: logSink)
            let destroyer = VMDestroyer(tart: tart, logger: shutdownLogger)
            let shutdownCoordinator = VMShutdownCoordinator(destroyer: destroyer)
            let runnerControl = RunnerControl()
            cleanupTargets.append(shutdownCoordinator)
            runnerControls.append(runnerControl)
            let github = try githubService(for: runnerConfig.provisioner)
            let runner = Runner(
                tart: tart,
                github: github,
                provisioner: provisioner,
                config: runnerConfig,
                shutdownCoordinator: shutdownCoordinator,
                control: runnerControl,
                vmName: runnerName,
                logLabel: logLabel,
                logLevel: level,
                logSink: logSink
            )
            runners.append(runner)
        }
        let shutdownLogger = Logger(label: "sand.shutdown", minimumLevel: level, sink: logSink)
        let signalHandler = SignalHandler(signals: [SIGINT, SIGTERM], logger: shutdownLogger) {
            for control in runnerControls {
                control.terminateProvisioning()
                control.cancelHealthCheck()
            }
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
