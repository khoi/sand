import Foundation

struct Runner: Sendable {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let runnerVersionResolver: GitHubRunnerVersionResolver
    let config: Config.RunnerConfig
    let shutdownCoordinator: VMShutdownCoordinator
    let control: RunnerControl
    let vmName: String
    private let logger: Logger
    private let vmLogger: Logger
    private let restartBackoff = RestartBackoff()
    private let sshRetryDelays: [TimeInterval] = [1, 2, 4, 8, 16, 30, 30, 30, 30, 30]
    private static let healthCheckExitMarker = "__SAND_HEALTHCHECK_EXIT_CODE__"

    enum RunnerError: Error {
        case missingGitHub
        case missingScript
        case invalidMountHostPath(String)
    }

    private struct RunnerCacheInfo {
        let hostPath: String
        let name: String
    }

    init(
        tart: Tart,
        github: GitHubService?,
        provisioner: GitHubProvisioner,
        runnerVersionResolver: GitHubRunnerVersionResolver,
        config: Config.RunnerConfig,
        shutdownCoordinator: VMShutdownCoordinator,
        control: RunnerControl,
        vmName: String,
        logLabel: String,
        logLevel: LogLevel,
        logSink: LogFileSink?
    ) {
        self.tart = tart
        self.github = github
        self.provisioner = provisioner
        self.runnerVersionResolver = runnerVersionResolver
        self.config = config
        self.shutdownCoordinator = shutdownCoordinator
        self.control = control
        self.vmName = vmName
        self.logger = Logger(label: "host.\(logLabel)", minimumLevel: logLevel, sink: logSink)
        self.vmLogger = Logger(label: "vm.\(logLabel)", minimumLevel: logLevel, sink: logSink)
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
        let stopAfterLabel = config.stopAfter.map(String.init) ?? "nil"
        logger.debug("runOnce start (vm=\(vmName), stopAfter=\(stopAfterLabel))")
        await applyRestartBackoffIfNeeded()
        let name = vmName
        let vm = config.vm
        let provisionerConfig = config.provisioner
        let source = vm.source.resolvedSource
        logger.info("prepare source \(source)")
        try await tart.prepare(source: source)
        do {
            if try await tart.isRunning(name: name) {
                logger.info("VM \(name) already running, stopping before boot")
                try await tart.stop(name: name)
            }
        } catch {
            logger.warning("preflight cleanup failed: \(String(describing: error))")
        }
        logger.info("clone VM \(name) from \(source)")
        try await tart.clone(source: source, name: name)
        await shutdownCoordinator.activate(name: name)
        do {
            try await applyVMConfigIfNeeded(name: name, vm: vm)
        } catch {
            await shutdownCoordinator.cleanup()
            throw error
        }
        let runnerCacheInfo = prepareRunnerCacheInfo(for: config)
        if runnerCacheInfo == nil, config.provisioner.type == .github, config.vm.cache == nil {
            logger.info("runner cache disabled: missing vm.cache")
        }
        let directoryMounts = try buildDirectoryMounts(vm: vm, cacheInfo: runnerCacheInfo, includeCache: config.provisioner.type == .github)
        let runOptions = Tart.RunOptions(
            directoryMounts: directoryMounts,
            noAudio: vm.hardware?.audio == false,
            noGraphics: vm.run.noGraphics,
            noClipboard: vm.run.noClipboard
        )
        logRunOptions(name: name, options: runOptions)
        logger.info("boot VM \(name)")
        do {
            try await tart.run(name: name, options: runOptions)
        } catch {
            logger.error("tart run failed for \(name): \(String(describing: error))")
            await shutdownCoordinator.cleanup()
            throw error
        }
        await logVMStatusAfterBoot(name: name)
        logger.info("wait for VM IP")
        let ip: String
        do {
            ip = try await resolveIP(name: name)
        } catch {
            await shutdownCoordinator.cleanup()
            throw error
        }
        logger.info("VM IP \(ip)")
        let ssh = SSHClient(processRunner: tart.processRunner, host: ip, config: vm.ssh)
        guard await waitForSSH(ssh: ssh) else {
            logger.debug("waitForSSH failed; scheduling restart")
            await scheduleRestart(reason: .sshNotReady)
            await shutdownCoordinator.cleanup()
            return
        }
        if let preRun = config.preRun {
            logger.info("run preRun")
            logScript(preRun)
            do {
                let result = try await execWithRetry(command: preRun, ssh: ssh, stage: "preRun")
                if let result {
                    logIfNonEmpty(label: "stdout", text: result.stdout)
                    logIfNonEmpty(label: "stderr", text: result.stderr)
                }
                logger.info("preRun finished")
            } catch {
                if await handleStageFailure(error, stage: "preRun", healthCheckState: nil) {
                    await shutdownCoordinator.cleanup()
                    return
                }
                await shutdownCoordinator.cleanup()
                throw error
            }
        }
        let healthCheckState = HealthCheckState()
        logger.debug("healthCheck task preparing (vm=\(name))")
        let healthCheckTask = startHealthCheck(
            healthCheck: config.healthCheck ?? .standard,
            vmName: name,
            ssh: vm.ssh,
            control: control,
            state: healthCheckState
        )
        await control.setHealthCheckTask(healthCheckTask)
        func stopHealthCheck(_ task: Task<Void, Never>) async {
            logger.debug("healthCheck task cancel requested")
            task.cancel()
            await control.clearHealthCheckTask()
        }
        do {
            switch provisionerConfig.type {
            case .script:
                guard let run = provisionerConfig.script?.run else {
                    throw RunnerError.missingScript
                }
                logger.info("run script provisioner")
                let outcome = await runProvisionerCommands([run], ssh: ssh, healthCheckState: healthCheckState)
                switch outcome {
                case .completed:
                    logger.info("script provisioner finished")
                case let .failed(error):
                    if await handleStageFailure(error, stage: "provisioner", healthCheckState: healthCheckState) {
                        await stopHealthCheck(healthCheckTask)
                        await shutdownCoordinator.cleanup()
                        return
                    }
                    await stopHealthCheck(healthCheckTask)
                    await shutdownCoordinator.cleanup()
                    throw error
                case let .healthCheckFailed(message):
                    await scheduleRestart(reason: .healthCheckFailed(message))
                    await stopHealthCheck(healthCheckTask)
                    await shutdownCoordinator.cleanup()
                    return
                }
            case .github:
                guard let github, let githubConfig = provisionerConfig.github else {
                    throw RunnerError.missingGitHub
                }
                logger.info("run github provisioner")
                let token = try await github.runnerRegistrationToken()
                let runnerVersion = try await resolveRunnerVersion(cacheInfo: runnerCacheInfo)
                if let runnerCacheInfo {
                    await preseedRunnerCacheIfPossible(
                        cacheInfo: runnerCacheInfo,
                        ssh: ssh,
                        runnerVersion: runnerVersion
                    )
                }
                let commands = provisioner.script(
                    config: githubConfig,
                    runnerToken: token,
                    runnerVersion: runnerVersion,
                    cacheDirectory: runnerCacheInfo?.name
                )
                let outcome = await runProvisionerCommands(commands, ssh: ssh, healthCheckState: healthCheckState)
                switch outcome {
                case .completed:
                    logger.warning("github provisioner completed; runner exited, restarting VM")
                    await scheduleRestart(reason: .provisionerExited)
                    await stopHealthCheck(healthCheckTask)
                    await shutdownCoordinator.cleanup()
                    return
                case let .failed(error):
                    if await handleStageFailure(error, stage: "provisioner", healthCheckState: healthCheckState) {
                        await stopHealthCheck(healthCheckTask)
                        await shutdownCoordinator.cleanup()
                        return
                    }
                    await stopHealthCheck(healthCheckTask)
                    await shutdownCoordinator.cleanup()
                    throw error
                case let .healthCheckFailed(message):
                    await scheduleRestart(reason: .healthCheckFailed(message))
                    await stopHealthCheck(healthCheckTask)
                    await shutdownCoordinator.cleanup()
                    return
                }
            }
        } catch {
            if await handleStageFailure(error, stage: "provisioner", healthCheckState: healthCheckState) {
                await stopHealthCheck(healthCheckTask)
                await shutdownCoordinator.cleanup()
                return
            }
            await stopHealthCheck(healthCheckTask)
            await shutdownCoordinator.cleanup()
            throw error
        }
        if let postRun = config.postRun {
            logger.info("run postRun")
            logScript(postRun)
            do {
                let result = try await execWithRetry(command: postRun, ssh: ssh, stage: "postRun")
                if let result {
                    logIfNonEmpty(label: "stdout", text: result.stdout)
                    logIfNonEmpty(label: "stderr", text: result.stderr)
                }
                logger.info("postRun finished")
            } catch {
                if await handleStageFailure(error, stage: "postRun", healthCheckState: healthCheckState) {
                    await stopHealthCheck(healthCheckTask)
                    await shutdownCoordinator.cleanup()
                    return
                }
                await stopHealthCheck(healthCheckTask)
                await shutdownCoordinator.cleanup()
                throw error
            }
        }
        if let message = await healthCheckState.failureMessage() {
            await scheduleRestart(reason: .healthCheckFailed(message))
            await stopHealthCheck(healthCheckTask)
            await shutdownCoordinator.cleanup()
            return
        }
        await restartBackoff.reset()
        await stopHealthCheck(healthCheckTask)
        await shutdownCoordinator.cleanup()
        logger.debug("runOnce complete (vm=\(vmName))")
    }

    private func applyVMConfigIfNeeded(name: String, vm: Config.VM) async throws {
        let hardware = vm.hardware
        let display: Tart.Display? = hardware?.display.map {
            Tart.Display(width: $0.width, height: $0.height, unit: $0.unit?.rawValue)
        }
        let displayRefit = hardware?.display?.refit
        let memoryMb = hardware?.ramGb.map { $0 * 1024 }
        let cpuCores = hardware?.cpuCores
        let diskSizeGb = vm.diskSizeGb
        guard cpuCores != nil || memoryMb != nil || display != nil || displayRefit != nil || diskSizeGb != nil else {
            return
        }
        try await tart.set(
            name: name,
            cpuCores: cpuCores,
            memoryMb: memoryMb,
            display: display,
            displayRefit: displayRefit,
            diskSizeGb: diskSizeGb
        )
    }

    private func prepareRunnerCacheInfo(for config: Config.RunnerConfig) -> RunnerCacheInfo? {
        guard config.provisioner.type == .github else {
            return nil
        }
        guard let cache = config.vm.cache else {
            return nil
        }
        let name = Config.resolveMountName(hostPath: cache.hostPath, name: cache.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let hostPath = cache.hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || hostPath.isEmpty {
            return nil
        }
        do {
            try ensureDirectoryExists(hostPath)
        } catch {
            logger.warning("runner cache host could not be prepared at \(hostPath): \(String(describing: error))")
            return nil
        }
        logger.info("runner cache enabled: \(hostPath) -> \(name)")
        return RunnerCacheInfo(hostPath: hostPath, name: name)
    }

    private func resolveRunnerVersion(cacheInfo: RunnerCacheInfo?) async throws -> String {
        do {
            let version = try await runnerVersionResolver.latestVersion()
            logger.info("resolved latest Actions runner version: \(version)")
            return version
        } catch {
            guard let cacheInfo,
                  let cachedVersion = GitHubRunnerVersionResolver.newestCachedVersion(in: cacheInfo.hostPath) else {
                logger.error("failed to resolve latest Actions runner version: \(String(describing: error))")
                throw error
            }
            logger.warning("failed to resolve latest Actions runner version; using cached version \(cachedVersion): \(String(describing: error))")
            return cachedVersion
        }
    }

    private func preseedRunnerCacheIfPossible(
        cacheInfo: RunnerCacheInfo,
        ssh: SSHClient,
        runnerVersion: String
    ) async {
        let missing = DependencyChecker.missingCommands(["scp"])
        if !missing.isEmpty {
            logger.warning("runner cache preseed skipped: missing scp in PATH")
            return
        }
        let assetName = await resolveRunnerAssetName(ssh: ssh, runnerVersion: runnerVersion)
        guard let assetName else {
            logger.warning("runner cache preseed skipped: unable to resolve runner asset name")
            return
        }
        let hostFile = (cacheInfo.hostPath as NSString).appendingPathComponent(assetName)
        guard FileManager.default.fileExists(atPath: hostFile) else {
            logger.info("runner cache preseed skipped: host cache file not found at \(hostFile)")
            return
        }
        let remotePath = await resolveRemoteHome(ssh: ssh)
            .map { "\($0)/actions-runner.tar.gz" } ?? "actions-runner.tar.gz"
        if let _ = try? await ssh.exec(command: "test -f \(remotePath)") {
            logger.info("runner cache preseed skipped: \(remotePath) already present")
            return
        }
        logger.info("runner cache preseed: \(hostFile) -> \(remotePath)")
        do {
            _ = try await ssh.copy(localPath: hostFile, remotePath: remotePath)
        } catch {
            logger.warning("runner cache preseed failed: \(String(describing: error))")
        }
    }

    private func resolveRunnerAssetName(ssh: SSHClient, runnerVersion: String) async -> String? {
        do {
            guard let result = try await ssh.exec(command: "uname -s; uname -m") else {
                return nil
            }
            let lines = result.stdout
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard lines.count >= 2 else {
                return nil
            }
            return GitHubProvisioner.runnerAssetName(
                os: lines[0],
                arch: lines[1],
                version: runnerVersion
            )
        } catch {
            logger.warning("runner cache preseed failed to read OS/arch: \(String(describing: error))")
            return nil
        }
    }

    private func resolveRemoteHome(ssh: SSHClient) async -> String? {
        do {
            guard let result = try await ssh.exec(command: "printf %s \"$HOME\"") else {
                return nil
            }
            let home = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return home.isEmpty ? nil : home
        } catch {
            logger.warning("runner cache preseed failed to read remote home: \(String(describing: error))")
            return nil
        }
    }

    private func waitForSSH(ssh: SSHClient) async -> Bool {
        var attempt = 0
        var stoppedChecks = 0
        let maxRetries = ssh.config.connectMaxRetries
        logger.debug("waitForSSH start (vm=\(vmName), maxRetries=\(maxRetries.map(String.init) ?? "nil"))")
        while true {
            if let maxRetries, attempt >= maxRetries {
                logger.warning("SSH not ready after \(maxRetries) attempts, restarting VM")
                return false
            }
            attempt += 1
            do {
                let status = try await tart.status(name: vmName)
                logger.debug("waitForSSH attempt \(attempt): VM status \(statusLabel(status))")
                if status != .running {
                    let reason = status == .missing ? "missing" : "stopped"
                    if status == .missing {
                        logger.warning("VM \(vmName) not running (\(reason)) while waiting for SSH (attempt \(attempt)), restarting VM")
                        return false
                    }
                    stoppedChecks += 1
                    if stoppedChecks >= 5 {
                        logger.warning("VM \(vmName) not running (\(reason)) after \(stoppedChecks) checks, restarting VM")
                        return false
                    }
                    logger.info("VM \(vmName) not running (\(reason)) while waiting for SSH (attempt \(attempt)), retrying")
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        return false
                    }
                    continue
                }
            } catch {
                logger.warning("Failed to check VM \(vmName) running state: \(String(describing: error))")
            }
            do {
                try await ssh.checkConnection()
                stoppedChecks = 0
                logger.info("SSH ready after \(attempt) attempt(s)")
                return true
            } catch {
                logger.debug("SSH checkConnection failed (attempt \(attempt)): \(String(describing: error))")
                if let maxRetries {
                    logger.info("SSH not ready, retrying in 1s (attempt \(attempt)/\(maxRetries))")
                } else {
                    logger.info("SSH not ready, retrying in 1s (attempt \(attempt))")
                }
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return false
                }
            }
        }
    }

    private func resolveIP(name: String) async throws -> String {
        var attempt = 0
        while true {
            attempt += 1
            do {
                logger.info("resolve VM IP (attempt \(attempt))")
                return try await tart.ip(name: name, wait: 180)
            } catch {
                logger.warning("resolve VM IP failed (attempt \(attempt)): \(String(describing: error))")
                if attempt >= 3 {
                    throw error
                }
                try await Task.sleep(nanoseconds: nanos(from: 5))
            }
        }
    }

    private func resolveHealthCheckIP(name: String, interval: TimeInterval) async -> String? {
        let waitSeconds = max(5, Int(min(interval, 10)))
        do {
            return try await tart.ip(name: name, wait: waitSeconds)
        } catch {
            logger.debug("healthCheck failed to resolve IP: \(String(describing: error))")
            return nil
        }
    }

    private func startHealthCheck(
        healthCheck: Config.HealthCheck,
        vmName: String,
        ssh: Config.SSH,
        control: RunnerControl,
        state: HealthCheckState
    ) -> Task<Void, Never> {
        logger.info("healthCheck starting in \(healthCheck.delay)s")
        return Task {
            if healthCheck.delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: nanos(from: healthCheck.delay))
                } catch {
                    self.logger.debug("healthCheck delay sleep cancelled")
                    return
                }
            }
            guard !Task.isCancelled else {
                self.logger.debug("healthCheck task cancelled before activation")
                return
            }
            logger.info("healthCheck active (interval: \(healthCheck.interval)s)")
            let activationTime = Date()
            var sawSuccess = false
            let startupGrace = max(healthCheck.interval, 10)
            let healthCheckLabel = commandSummary(healthCheck.command)
            let healthCheckDescriptor = healthCheckLabel.isEmpty ? "healthCheck" : "healthCheck (\(healthCheckLabel))"
            logger.info("healthCheck command: \(healthCheck.command)")
            while !Task.isCancelled {
                self.logger.debug("healthCheck tick (vm=\(vmName))")
                do {
                    let status = try await tart.status(name: vmName)
                    self.logger.debug("healthCheck VM status: \(statusLabel(status))")
                    if status != .running {
                        let message: String
                        switch status {
                        case .missing:
                            message = "vm missing"
                        case .stopped:
                            message = "vm stopped"
                        case .running:
                            message = "vm running"
                        }
                        logger.warning("VM \(vmName) not running (\(message)), marking healthCheck failed")
                        await state.markFailed(message: message)
                        await control.terminateProvisioning()
                        return
                    }
                } catch {
                    logger.warning("Failed to check VM \(vmName) running state: \(String(describing: error))")
                }
                do {
                    guard let ip = await resolveHealthCheckIP(name: vmName, interval: healthCheck.interval) else {
                        self.logger.debug("healthCheck failed to resolve IP; retrying")
                        continue
                    }
                    self.logger.debug("healthCheck resolved IP: \(ip)")
                    let probe = SSHClient(processRunner: tart.processRunner, host: ip, config: ssh)
                    let probeCommand = wrapHealthCheckCommand(healthCheck.command)
                    let result = try await probe.exec(command: probeCommand)
                    let output = result?.stdout ?? ""
                    let exitCode = parseHealthCheckExitCode(output: output) ?? 1
                    self.logger.debug("healthCheck exit code \(exitCode)")
                    if exitCode == 0 {
                        sawSuccess = true
                        self.logger.debug("healthCheck success")
                    } else {
                        let filteredOutput = stripHealthCheckMarker(output: output)
                        let outputLabel = healthCheckLabel.isEmpty ? "healthCheck output" : "healthCheck output (\(healthCheckLabel))"
                        logIfNonEmpty(label: outputLabel, text: filteredOutput)
                        let message = "exit code \(exitCode)"
                        let inStartupGrace = !sawSuccess && Date().timeIntervalSince(activationTime) < startupGrace
                        if inStartupGrace {
                            logger.warning("\(healthCheckDescriptor) failed with \(message) during startup grace, retrying")
                        } else {
                            logger.warning("\(healthCheckDescriptor) failed with \(message), marking healthCheck failed")
                            await state.markFailed(message: message)
                            await control.terminateProvisioning()
                            return
                        }
                    }
                } catch {
                    logger.warning("\(healthCheckDescriptor) error (will retry): \(String(describing: error))")
                }
                do {
                    try await Task.sleep(nanoseconds: nanos(from: healthCheck.interval))
                } catch {
                    self.logger.debug("healthCheck interval sleep cancelled")
                    return
                }
            }
            self.logger.debug("healthCheck task cancelled (vm=\(vmName))")
        }
    }

    private enum ProvisionerOutcome {
        case completed(ProcessResult)
        case failed(Error)
        case healthCheckFailed(String)
    }

    private enum ProvisionerSequenceOutcome {
        case completed
        case failed(Error)
        case healthCheckFailed(String)
    }

    private func runProvisionerCommands(
        _ commands: [String],
        ssh: SSHClient,
        healthCheckState: HealthCheckState
    ) async -> ProvisionerSequenceOutcome {
        for command in commands {
            let outcome = await runProvisionerCommand(command, ssh: ssh, healthCheckState: healthCheckState)
            switch outcome {
            case .completed:
                continue
            case let .failed(error):
                return .failed(error)
            case let .healthCheckFailed(message):
                return .healthCheckFailed(message)
            }
        }
        return .completed
    }

    private func runProvisionerCommand(
        _ command: String,
        ssh: SSHClient,
        healthCheckState: HealthCheckState
    ) async -> ProvisionerOutcome {
        logScript(command)
        var attempt = 0
        while true {
            do {
                let commandLabel = commandSummary(command)
                let labeledCommand = commandLabel.isEmpty ? "provisioner command" : "provisioner command (\(commandLabel))"
                logger.debug("\(labeledCommand) starting (attempt \(attempt + 1))")
                let handle = try ssh.start(command: command)
                await control.setProvisioningHandle(handle)
                logger.debug("\(labeledCommand) started; awaiting completion or healthCheck failure")
                let outcome = await awaitProvisionerCommand(handle: handle, healthCheckState: healthCheckState)
                switch outcome {
                case let .completed(result):
                    let stdoutLabel = commandLabel.isEmpty ? "stdout" : "stdout (\(commandLabel))"
                    let stderrLabel = commandLabel.isEmpty ? "stderr" : "stderr (\(commandLabel))"
                    logIfNonEmpty(label: stdoutLabel, text: result.stdout)
                    logIfNonEmpty(label: stderrLabel, text: result.stderr)
                    logCacheStatusIfPresent(output: result.stdout)
                    let completionLabel = commandLabel.isEmpty ? "provisioner command" : "provisioner command (\(commandLabel))"
                    logger.info("\(completionLabel) completed with exit code \(result.exitCode)")
                    if isRunnerCommand(command) {
                        logger.warning("github runner exited with code \(result.exitCode)")
                    }
                    await control.clearProvisioningHandle(handle)
                    return .completed(result)
                case let .failed(error):
                    if await retrySSHIfNeeded(error: error, stage: "provisioner", attempt: &attempt) {
                        await control.clearProvisioningHandle(handle)
                        continue
                    }
                    await control.clearProvisioningHandle(handle)
                    return .failed(error)
                case let .healthCheckFailed(message):
                    logger.warning("healthCheck failed; terminating provisioner command wait: \(message)")
                    await control.terminateProvisioning()
                    Task.detached {
                        _ = try? await handle.waitAsync()
                    }
                    await control.clearProvisioningHandle(handle)
                    return .healthCheckFailed(message)
                }
            } catch {
                if await retrySSHIfNeeded(error: error, stage: "provisioner", attempt: &attempt) {
                    continue
                }
                return .failed(error)
            }
        }
    }

    private func awaitProvisionerCommand(
        handle: ProcessHandle,
        healthCheckState: HealthCheckState
    ) async -> ProvisionerOutcome {
        await withTaskGroup(of: ProvisionerOutcome?.self) { group in
            group.addTask {
                do {
                    let result = try await handle.waitAsync()
                    return .completed(result)
                } catch {
                    return .failed(error)
                }
            }
            group.addTask {
                do {
                    let message = try await healthCheckState.waitForFailure()
                    return .healthCheckFailed(message)
                } catch is CancellationError {
                    return nil
                } catch {
                    return .failed(error)
                }
            }
            while let outcome = await group.next() {
                if let outcome {
                    logger.debug("provisioner outcome received: \(provisionerOutcomeLabel(outcome))")
                    group.cancelAll()
                    return outcome
                }
            }
            return .failed(ProcessRunnerError.invalidCommand)
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

    private func stripHealthCheckMarker(output: String) -> String {
        let marker = Runner.healthCheckExitMarker + ":"
        let lines = output.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix(marker) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func execWithRetry(command: String, ssh: SSHClient, stage: String) async throws -> ProcessResult? {
        var attempt = 0
        while true {
            do {
                return try await ssh.exec(command: command)
            } catch {
                if await retrySSHIfNeeded(error: error, stage: stage, attempt: &attempt) {
                    continue
                }
                throw error
            }
        }
    }

    private func retrySSHIfNeeded(error: Error, stage: String, attempt: inout Int) async -> Bool {
        guard shouldRetrySSH(error), attempt < sshRetryDelays.count else {
            return false
        }
        let delay = sshRetryDelays[attempt]
        attempt += 1
        let attemptLabel = "\(attempt)/\(sshRetryDelays.count)"
        if delay > 0 {
            logger.warning("SSH failed during \(stage), retrying in \(delay)s (attempt \(attemptLabel))")
        } else {
            logger.warning("SSH failed during \(stage), retrying (attempt \(attemptLabel))")
        }
        do {
            try await Task.sleep(nanoseconds: nanos(from: delay))
        } catch {
            return false
        }
        return true
    }

    private func shouldRetrySSH(_ error: Error) -> Bool {
        guard let runnerError = error as? ProcessRunnerError else {
            return false
        }
        switch runnerError {
        case let .failed(exitCode, _, _, command):
            guard exitCode == 255 else {
                return false
            }
            return command.first == "sshpass"
        case .invalidCommand:
            return false
        }
    }

    private func scheduleRestart(reason: RestartReason) async {
        logger.debug("restart requested (\(reason))")
        let delay = await restartBackoff.schedule(reason: reason)
        let snapshot = await restartBackoff.snapshot()
        logger.debug("restart backoff state: \(snapshot)")
        if delay > 0 {
            logger.warning("restart scheduled in \(delay)s (\(reason))")
        } else {
            logger.warning("restart scheduled (\(reason))")
        }
    }

    private func applyRestartBackoffIfNeeded() async {
        let (delay, reason) = await restartBackoff.takePending()
        guard delay > 0 else {
            logger.debug("restart backoff: none pending")
            return
        }
        if let reason {
            logger.debug("restart backoff pending \(delay)s (\(reason))")
        } else {
            logger.debug("restart backoff pending \(delay)s (no reason)")
        }
        if let reason {
            logger.warning("restart backoff \(delay)s (\(reason))")
        } else {
            logger.warning("restart backoff \(delay)s")
        }
        do {
            try await Task.sleep(nanoseconds: nanos(from: delay))
        } catch {
            return
        }
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

    private func commandSummary(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        let firstLine = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let compact = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else {
            return ""
        }
        if compact.count > 80 {
            return String(compact.prefix(77)) + "..."
        }
        return compact
    }

    private func logCacheStatusIfPresent(output: String) {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let prefixes = [
            "runner cache hit:",
            "runner cache miss:",
            "runner cache populated:"
        ]
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            if prefixes.contains(where: { trimmed.hasPrefix($0) }) {
                logger.info(trimmed)
            }
        }
    }

    private func isRunnerCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        guard !firstToken.isEmpty else {
            return false
        }
        return firstToken.hasSuffix("actions-runner/run.sh")
    }

    private func logRunOptions(name: String, options: Tart.RunOptions) {
        logger.info("VM \(name) run options: noGraphics=\(options.noGraphics) noAudio=\(options.noAudio) noClipboard=\(options.noClipboard)")
        if options.directoryMounts.isEmpty {
            logger.info("VM \(name) mounts: none")
            return
        }
        for mount in options.directoryMounts {
            let mode = mount.readOnly ? "ro" : "rw"
            logger.info("VM \(name) mount: \(mount.name) <- \(mount.hostPath) (\(mode))")
        }
    }

    private func logVMStatusAfterBoot(name: String) async {
        do {
            let status = try await tart.status(name: name)
            logger.info("VM \(name) status after tart run: \(statusLabel(status))")
        } catch {
            logger.warning("Failed to read VM \(name) status after tart run: \(String(describing: error))")
        }
    }

    private func statusLabel(_ status: Tart.VMStatus) -> String {
        switch status {
        case .missing:
            return "missing"
        case .stopped:
            return "stopped"
        case .running:
            return "running"
        }
    }

    private func logScript(_ script: String) {
        vmLogger.log(.info, "[executing]\n\(script)")
    }

    private func handleStageFailure(_ error: Error, stage: String, healthCheckState: HealthCheckState?) async -> Bool {
        if let healthCheckState, let message = await healthCheckState.failureMessage() {
            logger.debug("\(stage) failed while healthCheck already failed: \(message)")
            await scheduleRestart(reason: .healthCheckFailed(message))
            return true
        }
        logStageFailure(error, stage: stage)
        guard config.stopAfter == nil else {
            logger.debug("\(stage) failed; stopAfter set, not restarting")
            return false
        }
        logger.warning("\(stage) failed, restarting VM")
        await scheduleRestart(reason: .stageFailed(stage))
        return true
    }

    private func logStageFailure(_ error: Error, stage: String) {
        if let runnerError = error as? ProcessRunnerError {
            switch runnerError {
            case let .failed(exitCode, stdout, stderr, _):
                logger.error("\(stage) failed with exit code \(exitCode)")
                logIfNonEmpty(label: "stdout", text: stdout)
                logIfNonEmpty(label: "stderr", text: stderr)
            case .invalidCommand:
                logger.error("\(stage) failed: invalid command")
            }
            return
        }
        logger.error("\(stage) failed: \(String(describing: error))")
    }

    private func provisionerOutcomeLabel(_ outcome: ProvisionerOutcome) -> String {
        switch outcome {
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .healthCheckFailed:
            return "healthCheckFailed"
        }
    }

    private func buildDirectoryMounts(
        vm: Config.VM,
        cacheInfo: RunnerCacheInfo?,
        includeCache: Bool
    ) throws -> [Tart.DirectoryMount] {
        var mounts: [Tart.DirectoryMount] = []
        for mount in vm.mounts {
            let hostPath = mount.hostPath
            try ensureDirectoryExists(hostPath)
            let name = Config.resolveMountName(hostPath: hostPath, name: mount.name)
            mounts.append(Tart.DirectoryMount(hostPath: hostPath, name: name, readOnly: mount.mode == .ro))
        }
        if includeCache, let cacheInfo {
            mounts.append(Tart.DirectoryMount(hostPath: cacheInfo.hostPath, name: cacheInfo.name, readOnly: false))
        }
        return mounts
    }

    private func ensureDirectoryExists(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RunnerError.invalidMountHostPath(path)
        }
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: trimmed, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw RunnerError.invalidMountHostPath(trimmed)
            }
            return
        }
        try fileManager.createDirectory(atPath: trimmed, withIntermediateDirectories: true)
    }
}

private actor HealthCheckState {
    private var failureMessageStorage: String?
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]

    func markFailed(message: String) {
        if failureMessageStorage == nil {
            failureMessageStorage = message
            let pending = waiters
            waiters = [:]
            for continuation in pending.values {
                continuation.resume(returning: message)
            }
        }
    }

    func failureMessage() -> String? {
        failureMessageStorage
    }

    func waitForFailure() async throws -> String {
        if let failureMessageStorage {
            return failureMessageStorage
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if let failureMessageStorage {
                    continuation.resume(returning: failureMessageStorage)
                    return
                }
                waiters[waiterID] = continuation
                if Task.isCancelled {
                    if let continuation = waiters.removeValue(forKey: waiterID) {
                        continuation.resume(throwing: CancellationError())
                    }
                }
            }
        }, onCancel: {
            Task { await cancelWaiter(id: waiterID) }
        })
    }

    private func cancelWaiter(id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
    }
}
