import Foundation
import Logging

struct Runner: @unchecked Sendable {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let config: Config
    let shutdownCoordinator: VMShutdownCoordinator
    let vmName: String
    private let logger: Logger
    private let vmLogger: Logger

    enum RunnerError: Error {
        case missingGitHub
        case missingScript
    }

    init(
        tart: Tart,
        github: GitHubService?,
        provisioner: GitHubProvisioner,
        config: Config,
        shutdownCoordinator: VMShutdownCoordinator,
        vmName: String,
        logLabel: String
    ) {
        self.tart = tart
        self.github = github
        self.provisioner = provisioner
        self.config = config
        self.shutdownCoordinator = shutdownCoordinator
        self.vmName = vmName
        self.logger = Logger(label: "host.\(logLabel)")
        self.vmLogger = Logger(label: "vm.\(logLabel)")
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
        let source = config.vm.source.resolvedSource
        logger.info("prepare source \(source)")
        try tart.prepare(source: source)
        logger.info("clone VM \(name) from \(source)")
        try tart.clone(source: source, name: name)
        shutdownCoordinator.activate(name: name)
        defer {
            shutdownCoordinator.cleanup(tart: tart)
        }
        try applyVMConfigIfNeeded(name: name)
        let runOptions = Tart.RunOptions(
            directoryMounts: config.vm.mounts.map {
                Tart.DirectoryMount(
                    hostPath: $0.hostPath,
                    guestFolder: $0.guestFolder,
                    readOnly: $0.readOnly,
                    tag: $0.tag
                )
            },
            noAudio: config.vm.hardware?.audio == false,
            noGraphics: config.vm.run.noGraphics,
            noClipboard: config.vm.run.noClipboard
        )
        logger.info("boot VM \(name)")
        try tart.run(name: name, options: runOptions)
        logger.info("wait for VM IP")
        let ip = try tart.ip(name: name, wait: 60)
        logger.info("VM IP \(ip)")
        let ssh = SSHClient(processRunner: tart.processRunner, host: ip, config: config.vm.ssh)
        try await waitForSSH(ssh: ssh)
        switch config.provisioner.type {
        case .script:
            guard let run = config.provisioner.script?.run else {
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
            guard let github, let githubConfig = config.provisioner.github else {
                throw RunnerError.missingGitHub
            }
            logger.info("run github provisioner")
            let token = try await github.runnerRegistrationToken()
            let commands = provisioner.script(config: githubConfig, runnerToken: token)
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
    }

    private func applyVMConfigIfNeeded(name: String) throws {
        let hardware = config.vm.hardware
        let display: Tart.Display? = hardware?.display.map {
            Tart.Display(width: $0.width, height: $0.height, unit: $0.unit?.rawValue)
        }
        let displayRefit = hardware?.display?.refit
        let memoryMb = hardware?.ramGb.map { $0 * 1024 }
        let cpuCores = hardware?.cpuCores
        let diskSizeGb = config.vm.diskSizeGb
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

    private func waitForSSH(ssh: SSHClient) async throws {
        var attempt = 0
        while true {
            attempt += 1
            do {
                try ssh.checkConnection()
                return
            } catch {
                logger.info("SSH not ready, retrying in 1s (attempt \(attempt))")
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func logLines(logger: Logger, _ text: String, level: Logger.Level) {
        for line in text.split(whereSeparator: \.isNewline) {
            logger.log(level: level, "\(line)")
        }
    }

    private func logIfNonEmpty(label: String, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        logLines(logger: vmLogger, "[\(label)] \(text)", level: .info)
    }

    private func logScript(_ script: String) {
        vmLogger.log(level: .info, "[executing]\n\(script)")
    }
}
