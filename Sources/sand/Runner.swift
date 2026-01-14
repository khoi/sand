import Foundation

struct Runner: @unchecked Sendable {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let config: Config.RunnerConfig
    let shutdownCoordinator: VMShutdownCoordinator
    let vmName: String
    private let logger: Logger
    private let vmLogger: Logger
    private static let healthCheckExitMarker = "__SAND_HEALTHCHECK_EXIT_CODE__"

    enum RunnerError: Error {
        case missingGitHub
        case missingScript
    }

    init(
        tart: Tart,
        github: GitHubService?,
        provisioner: GitHubProvisioner,
        config: Config.RunnerConfig,
        shutdownCoordinator: VMShutdownCoordinator,
        vmName: String,
        logLabel: String,
        logLevel: LogLevel
    ) {
        self.tart = tart
        self.github = github
        self.provisioner = provisioner
        self.config = config
        self.shutdownCoordinator = shutdownCoordinator
        self.vmName = vmName
        self.logger = Logger(label: "host.\(logLabel)", minimumLevel: logLevel)
        self.vmLogger = Logger(label: "vm.\(logLabel)", minimumLevel: logLevel)
    }

    func run() async throws {
        if let stopAfter = config.stopAfter {
            guard stopAfter > 0 else {
                return
            }
            for _ in 0..<stopAfter {
                try await runOnce()
            }
            return
        }
        while true {
            try await runOnce()
        }
    }

    private func runOnce() async throws {
        let name = vmName
        let vm = config.vm
        let provisionerConfig = config.provisioner
        let baseSource = vm.source.resolvedSource
        let source: String
        switch provisionerConfig.type {
        case .github:
            let prebuilder = GitHubRunnerPrebuilder(tart: tart, logger: logger, provisioner: provisioner)
            source = try await prebuilder.prebuiltSource(baseSource: baseSource, vm: vm)
        case .script:
            source = baseSource
        }
        logger.info("prepare source \(source)")
        try tart.prepare(source: source)
        logger.info("clone VM \(name) from \(source)")
        try tart.clone(source: source, name: name)
        shutdownCoordinator.activate(name: name)
        defer {
            shutdownCoordinator.cleanup()
        }
        try VMConfigurer.applyIfNeeded(tart: tart, name: name, vm: vm)
        let runOptions = Tart.RunOptions(
            directoryMounts: vm.mounts.map {
                Tart.DirectoryMount(
                    hostPath: $0.hostPath,
                    guestFolder: $0.guestFolder,
                    readOnly: $0.readOnly,
                    tag: $0.tag
                )
            },
            noAudio: vm.hardware?.audio == false,
            noGraphics: vm.run.noGraphics,
            noClipboard: vm.run.noClipboard
        )
        logger.info("boot VM \(name)")
        try tart.run(name: name, options: runOptions)
        logger.info("wait for VM IP")
        let ip = try tart.ip(name: name, wait: 60)
        logger.info("VM IP \(ip)")
        let ssh = SSHClient(processRunner: tart.processRunner, host: ip, config: vm.ssh)
        guard await SSHWaiter.wait(for: ssh, logger: logger) else {
            return
        }
        let healthCheckState = HealthCheckState()
        let healthCheckTask = startHealthCheckIfNeeded(
            healthCheck: config.healthCheck,
            ip: ip,
            ssh: vm.ssh,
            state: healthCheckState
        )
        defer {
            healthCheckTask?.cancel()
        }
        do {
            switch provisionerConfig.type {
            case .script:
                guard let run = provisionerConfig.script?.run else {
                    throw RunnerError.missingScript
                }
                logger.info("run script provisioner")
                logScript(run)
                let result = try ssh.exec(command: run)
                if let result {
                    logIfNonEmpty(label: "stdout", text: result.stdout)
                    logIfNonEmpty(label: "stderr", text: result.stderr)
                }
                logger.info("script provisioner finished")
            case .github:
                guard let github, let githubConfig = provisionerConfig.github else {
                    throw RunnerError.missingGitHub
                }
                logger.info("run github provisioner")
                let token = try await github.runnerRegistrationToken()
                let commands = provisioner.runScript(config: githubConfig, runnerToken: token)
                for command in commands {
                    logScript(command)
                    let result = try ssh.exec(command: command)
                    if let result {
                        logIfNonEmpty(label: "stdout", text: result.stdout)
                        logIfNonEmpty(label: "stderr", text: result.stderr)
                    }
                }
                logger.info("github provisioner finished")
            }
        } catch {
            if healthCheckState.failureMessage != nil {
                return
            }
            throw error
        }
        if healthCheckState.failureMessage != nil {
            return
        }
    }

    private func startHealthCheckIfNeeded(
        healthCheck: Config.HealthCheck?,
        ip: String,
        ssh: Config.SSH,
        state: HealthCheckState
    ) -> Task<Void, Never>? {
        guard let healthCheck else {
            return nil
        }
        logger.info("healthCheck starting in \(healthCheck.delay)s")
        return Task {
            if healthCheck.delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: nanos(from: healthCheck.delay))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled else {
                return
            }
            logger.info("healthCheck active (interval: \(healthCheck.interval)s)")
            while !Task.isCancelled {
                do {
                    let probe = SSHClient(processRunner: tart.processRunner, host: ip, config: ssh)
                    let probeCommand = wrapHealthCheckCommand(healthCheck.command)
                    let result = try probe.exec(command: probeCommand)
                    let output = result?.stdout ?? ""
                    let exitCode = parseHealthCheckExitCode(output: output) ?? 1
                    guard exitCode == 0 else {
                        let message = "exit code \(exitCode)"
                        logger.warning("healthCheck failed with \(message), restarting VM")
                        state.markFailed(message: message)
                        shutdownCoordinator.cleanup()
                        return
                    }
                } catch {
                    logger.warning("healthCheck error (will retry): \(String(describing: error))")
                }
                do {
                    try await Task.sleep(nanoseconds: nanos(from: healthCheck.interval))
                } catch {
                    return
                }
            }
        }
    }

    private func wrapHealthCheckCommand(_ command: String) -> String {
        let marker = Runner.healthCheckExitMarker
        return "set +e; (\(command)); code=$?; echo \(marker):$code; exit 0"
    }

    private func parseHealthCheckExitCode(output: String) -> Int? {
        let marker = Runner.healthCheckExitMarker + ":"
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            if line.hasPrefix(marker) {
                let value = line.dropFirst(marker.count)
                return Int(value)
            }
        }
        return nil
    }

    private func nanos(from seconds: TimeInterval) -> UInt64 {
        if seconds <= 0 {
            return 0
        }
        let nanos = seconds * 1_000_000_000
        if nanos >= Double(UInt64.max) {
            return UInt64.max
        }
        return UInt64(nanos)
    }

    private func logLines(logger: Logger, _ text: String, level: LogLevel) {
        for line in text.split(whereSeparator: \.isNewline) {
            logger.log(level, "\(line)")
        }
    }

    private func logIfNonEmpty(label: String, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        logLines(logger: vmLogger, "[\(label)] \(text)", level: .info)
    }

    private func logScript(_ script: String) {
        vmLogger.log(.info, "[executing]\n\(script)")
    }
}

private final class HealthCheckState: @unchecked Sendable {
    private let lock = NSLock()
    private var failureMessageStorage: String?

    func markFailed(message: String) {
        lock.lock()
        if failureMessageStorage == nil {
            failureMessageStorage = message
        }
        lock.unlock()
    }

    var failureMessage: String? {
        lock.lock()
        let value = failureMessageStorage
        lock.unlock()
        return value
    }
}
