import Foundation

struct Runner: @unchecked Sendable {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
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
    }

    init(
        tart: Tart,
        github: GitHubService?,
        provisioner: GitHubProvisioner,
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
        try tart.prepare(source: source)
        do {
            if try tart.isRunning(name: name) {
                logger.info("VM \(name) already running, stopping before boot")
                try tart.stop(name: name)
            }
        } catch {
            logger.warning("preflight cleanup failed: \(String(describing: error))")
        }
        logger.info("clone VM \(name) from \(source)")
        try tart.clone(source: source, name: name)
        shutdownCoordinator.activate(name: name)
        defer {
            shutdownCoordinator.cleanup()
        }
        try applyVMConfigIfNeeded(name: name, vm: vm)
        let runnerCacheDirectory = prepareRunnerCacheDirectory(for: config)
        let directoryMounts = vm.mounts.map { mount in
            Tart.DirectoryMount(
                hostPath: mount.hostPath,
                guestFolder: mount.guestFolder,
                readOnly: mount.readOnly,
                tag: resolvedMountTag(for: mount)
            )
        }
        let runOptions = Tart.RunOptions(
            directoryMounts: directoryMounts,
            noAudio: vm.hardware?.audio == false,
            noGraphics: vm.run.noGraphics,
            noClipboard: vm.run.noClipboard
        )
        logRunOptions(name: name, options: runOptions)
        logger.info("boot VM \(name)")
        do {
            try tart.run(name: name, options: runOptions)
        } catch {
            logger.error("tart run failed for \(name): \(String(describing: error))")
            throw error
        }
        logVMStatusAfterBoot(name: name)
        logger.info("wait for VM IP")
        let ip = try await resolveIP(name: name)
        logger.info("VM IP \(ip)")
        let ssh = SSHClient(processRunner: tart.processRunner, host: ip, config: vm.ssh)
        guard await waitForSSH(ssh: ssh) else {
            logger.debug("waitForSSH failed; scheduling restart")
            scheduleRestart(reason: .sshNotReady)
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
                if handleStageFailure(error, stage: "preRun", healthCheckState: nil) {
                    return
                }
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
        control.setHealthCheckTask(healthCheckTask)
        defer {
            logger.debug("healthCheck task cancel requested")
            healthCheckTask.cancel()
            control.clearHealthCheckTask()
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
                    if handleStageFailure(error, stage: "provisioner", healthCheckState: healthCheckState) {
                        return
                    }
                    throw error
                case let .healthCheckFailed(message):
                    scheduleRestart(reason: .healthCheckFailed(message))
                    return
                }
            case .github:
                guard let github, let githubConfig = provisionerConfig.github else {
                    throw RunnerError.missingGitHub
                }
                logger.info("run github provisioner")
                let token = try await github.runnerRegistrationToken()
                let commands = provisioner.script(config: githubConfig, runnerToken: token, cacheDirectory: runnerCacheDirectory)
                let outcome = await runProvisionerCommands(commands, ssh: ssh, healthCheckState: healthCheckState)
                switch outcome {
                case .completed:
                    logger.warning("github provisioner completed; runner exited, restarting VM")
                    scheduleRestart(reason: .provisionerExited)
                    return
                case let .failed(error):
                    if handleStageFailure(error, stage: "provisioner", healthCheckState: healthCheckState) {
                        return
                    }
                    throw error
                case let .healthCheckFailed(message):
                    scheduleRestart(reason: .healthCheckFailed(message))
                    return
                }
            }
        } catch {
            if handleStageFailure(error, stage: "provisioner", healthCheckState: healthCheckState) {
                return
            }
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
                if handleStageFailure(error, stage: "postRun", healthCheckState: healthCheckState) {
                    return
                }
                throw error
            }
        }
        if let message = healthCheckState.failureMessage {
            scheduleRestart(reason: .healthCheckFailed(message))
            return
        }
        restartBackoff.reset()
        logger.debug("runOnce complete (vm=\(vmName))")
    }

    private func applyVMConfigIfNeeded(name: String, vm: Config.VM) throws {
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
        try tart.set(
            name: name,
            cpuCores: cpuCores,
            memoryMb: memoryMb,
            display: display,
            displayRefit: displayRefit,
            diskSizeGb: diskSizeGb
        )
    }

    private func prepareRunnerCacheDirectory(for config: Config.RunnerConfig) -> String? {
        guard config.provisioner.type == .github else {
            return nil
        }
        let cacheMounts = config.vm.mounts.filter { $0.tag == GitHubProvisioner.runnerCacheMountTag }
        guard let cacheMount = cacheMounts.first else {
            return nil
        }
        if cacheMounts.count > 1 {
            logger.warning("multiple vm.mounts entries tagged \(GitHubProvisioner.runnerCacheMountTag); using the first")
        }
        let guestFolder = cacheMount.guestFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostPath = cacheMount.hostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if guestFolder.isEmpty || hostPath.isEmpty {
            return nil
        }
        var isDirectory: ObjCBool = false
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: hostPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                logger.warning("runner cache hostPath exists but is not a directory: \(hostPath)")
                return nil
            }
        } else {
            do {
                try fileManager.createDirectory(atPath: hostPath, withIntermediateDirectories: true)
            } catch {
                logger.warning("runner cache hostPath could not be created at \(hostPath): \(String(describing: error))")
                return nil
            }
        }
        logger.info("runner cache enabled via mount tag \(GitHubProvisioner.runnerCacheMountTag): \(hostPath) -> \(guestFolder)")
        return guestFolder
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
                let status = try tart.status(name: vmName)
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
                }
            } catch {
                logger.warning("Failed to check VM \(vmName) running state: \(String(describing: error))")
            }
            do {
                try ssh.checkConnection()
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
                return try tart.ip(name: name, wait: 180)
            } catch {
                logger.warning("resolve VM IP failed (attempt \(attempt)): \(String(describing: error))")
                if attempt >= 3 {
                    throw error
                }
                try await Task.sleep(nanoseconds: nanos(from: 5))
            }
        }
    }

    private func resolveHealthCheckIP(name: String, interval: TimeInterval) -> String? {
        let waitSeconds = max(5, Int(min(interval, 10)))
        do {
            return try tart.ip(name: name, wait: waitSeconds)
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
                    let status = try tart.status(name: vmName)
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
                        logger.warning("VM \(vmName) not running (\(message)), restarting VM")
                        scheduleRestart(reason: .healthCheckFailed(message))
                        state.markFailed(message: message)
                        control.terminateProvisioning()
                        shutdownCoordinator.cleanup()
                        return
                    }
                } catch {
                    logger.warning("Failed to check VM \(vmName) running state: \(String(describing: error))")
                }
                do {
                    guard let ip = resolveHealthCheckIP(name: vmName, interval: healthCheck.interval) else {
                        self.logger.debug("healthCheck failed to resolve IP; retrying")
                        continue
                    }
                    self.logger.debug("healthCheck resolved IP: \(ip)")
                    let probe = SSHClient(processRunner: tart.processRunner, host: ip, config: ssh)
                    let probeCommand = wrapHealthCheckCommand(healthCheck.command)
                    let result = try probe.exec(command: probeCommand)
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
                            logger.warning("\(healthCheckDescriptor) failed with \(message), restarting VM")
                            scheduleRestart(reason: .healthCheckFailed(message))
                            state.markFailed(message: message)
                            control.terminateProvisioning()
                            shutdownCoordinator.cleanup()
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
                control.setProvisioningHandle(handle)
                defer {
                    control.clearProvisioningHandle(handle)
                }
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
                    return .completed(result)
                case let .failed(error):
                    if await retrySSHIfNeeded(error: error, stage: "provisioner", attempt: &attempt) {
                        continue
                    }
                    return .failed(error)
                case let .healthCheckFailed(message):
                    logger.debug("provisioner command aborted due to healthCheck failure: \(message)")
                    control.terminateProvisioning()
                    Task.detached {
                        _ = try? handle.wait()
                    }
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
                    let result = try handle.wait()
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
                return try ssh.exec(command: command)
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

    private func scheduleRestart(reason: RestartReason) {
        logger.debug("restart requested (\(reason))")
        let delay = restartBackoff.schedule(reason: reason)
        logger.debug("restart backoff state: \(restartBackoff.snapshot())")
        if delay > 0 {
            logger.warning("restart scheduled in \(delay)s (\(reason))")
        } else {
            logger.warning("restart scheduled (\(reason))")
        }
    }

    private func applyRestartBackoffIfNeeded() async {
        let (delay, reason) = restartBackoff.takePending()
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
            let tagInfo = mount.tag.map { ", tag=\($0)" } ?? ""
            let mode = mount.readOnly ? "ro" : "rw"
            logger.info("VM \(name) mount: \(mount.guestFolder) <- \(mount.hostPath) (\(mode)\(tagInfo))")
        }
    }

    private func logVMStatusAfterBoot(name: String) {
        do {
            let status = try tart.status(name: name)
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

    private func resolvedMountTag(for mount: Config.DirectoryMount) -> String? {
        if mount.tag == GitHubProvisioner.runnerCacheMountTag {
            return nil
        }
        return mount.tag
    }

    private func logScript(_ script: String) {
        vmLogger.log(.info, "[executing]\n\(script)")
    }

    private func handleStageFailure(_ error: Error, stage: String, healthCheckState: HealthCheckState?) -> Bool {
        if let message = healthCheckState?.failureMessage {
            logger.debug("\(stage) failed while healthCheck already failed: \(message)")
            scheduleRestart(reason: .healthCheckFailed(message))
            return true
        }
        logStageFailure(error, stage: stage)
        guard config.stopAfter == nil else {
            logger.debug("\(stage) failed; stopAfter set, not restarting")
            return false
        }
        logger.warning("\(stage) failed, restarting VM")
        scheduleRestart(reason: .stageFailed(stage))
        shutdownCoordinator.cleanup()
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
}

private final class HealthCheckState: @unchecked Sendable {
    private let lock = NSLock()
    private var failureMessageStorage: String?
    private var waiters: [UUID: CheckedContinuation<String, Error>] = [:]

    func markFailed(message: String) {
        lock.lock()
        if failureMessageStorage == nil {
            failureMessageStorage = message
            let pending = waiters
            waiters = [:]
            lock.unlock()
            for continuation in pending.values {
                continuation.resume(returning: message)
            }
            return
        }
        lock.unlock()
    }

    var failureMessage: String? {
        lock.lock()
        let value = failureMessageStorage
        lock.unlock()
        return value
    }

    func waitForFailure() async throws -> String {
        if let failureMessage = failureMessage {
            return failureMessage
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let failureMessageStorage {
                    lock.unlock()
                    continuation.resume(returning: failureMessageStorage)
                    return
                }
                waiters[waiterID] = continuation
                lock.unlock()
                if Task.isCancelled {
                    lock.lock()
                    if let continuation = waiters.removeValue(forKey: waiterID) {
                        lock.unlock()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    lock.unlock()
                }
            }
        }, onCancel: {
            lock.lock()
            if let continuation = waiters.removeValue(forKey: waiterID) {
                lock.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            lock.unlock()
        })
    }
}
