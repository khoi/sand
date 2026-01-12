import Foundation
import Logging

struct Runner {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let config: Config
    private let logger = Logger(label: "sand.runner")
    private let vmLogger = Logger(label: "vm")
    private let execRetryAttempts = 12
    private let execRetryDelaySeconds: UInt64 = 5

    enum RunnerError: Error {
        case missingGitHub
        case missingScript
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
        let name = "ephemeral"
        let source = config.vm.source.resolvedSource
        logger.info("prepare source \(source)")
        try tart.prepare(source: source)
        logger.info("clone VM \(name) from \(source)")
        try tart.clone(source: source, name: name)
        defer {
            logger.info("delete VM \(name)")
            try? tart.delete(name: name)
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
        defer {
            logger.info("stop VM \(name)")
            try? tart.stop(name: name)
        }
        logger.info("wait for VM IP")
        let ip = try tart.ip(name: name, wait: 60)
        logger.info("VM IP \(ip)")
        switch config.provisioner.type {
        case .script:
            guard let run = config.provisioner.script?.run else {
                throw RunnerError.missingScript
            }
            logger.info("run script provisioner")
            let result = try await execWithRetry(name: name, command: run)
            if let result {
                logLines(logger: vmLogger, "[stdout] \(result.stdout)", level: .info)
                logLines(logger: vmLogger, "[stderr] \(result.stderr)", level: .info)
            }
            logger.info("script provisioner finished")
        case .github:
            guard let github, let githubConfig = config.provisioner.github else {
                throw RunnerError.missingGitHub
            }
            logger.info("run github provisioner")
            let token = try await github.runnerRegistrationToken()
            let downloadURL = try await github.runnerDownloadURL()
            let script = provisioner.script(config: githubConfig, runnerToken: token, downloadURL: downloadURL)
            _ = try await execWithRetry(name: name, command: script)
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

    private func execWithRetry(name: String, command: String) async throws -> ProcessResult? {
        for attempt in 1...execRetryAttempts {
            do {
                return try tart.exec(name: name, command: command)
            } catch {
                guard isGuestAgentUnavailable(error), attempt < execRetryAttempts else {
                    throw error
                }
                logger.info("tart exec failed (guest agent not ready), retrying in \(self.execRetryDelaySeconds)s (attempt \(attempt + 1) of \(self.execRetryAttempts))")
                try await Task.sleep(nanoseconds: execRetryDelaySeconds * 1_000_000_000)
            }
        }
        return nil
    }

    private func isGuestAgentUnavailable(_ error: Error) -> Bool {
        guard case let ProcessRunnerError.failed(_, _, stderr, _) = error else {
            return false
        }
        return stderr.localizedCaseInsensitiveContains("GRPCConnectionPoolError")
            || stderr.localizedCaseInsensitiveContains("guest agent")
    }

    private func logLines(logger: Logger, _ text: String, level: Logger.Level) {
        for line in text.split(whereSeparator: \.isNewline) {
            logger.log(level: level, "\(line)")
        }
    }
}
