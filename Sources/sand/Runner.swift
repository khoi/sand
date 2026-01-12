import Foundation
import OSLog

struct Runner {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let config: Config
    private let logger = Logger(subsystem: "sand", category: "runner")
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
        logger.info("prepare source \(self.config.source, privacy: .public)")
        try tart.prepare(source: config.source)
        logger.info("clone VM \(name, privacy: .public) from \(self.config.source, privacy: .public)")
        try tart.clone(source: config.source, name: name)
        defer {
            logger.info("delete VM \(name, privacy: .public)")
            try? tart.delete(name: name)
        }
        logger.info("boot VM \(name, privacy: .public)")
        try tart.run(name: name)
        defer {
            logger.info("stop VM \(name, privacy: .public)")
            try? tart.stop(name: name)
        }
        logger.info("wait for VM IP")
        let ip = try tart.ip(name: name, wait: 60)
        logger.info("VM IP \(ip, privacy: .public)")
        switch config.provisioner.type {
        case .script:
            guard let run = config.provisioner.script?.run else {
                throw RunnerError.missingScript
            }
            logger.info("run script provisioner")
            let result = try await execWithRetry(name: name, command: run)
            if let stdout = result?.stdout.data(using: .utf8) {
                FileHandle.standardOutput.write(stdout)
            }
            if let stderr = result?.stderr.data(using: .utf8) {
                FileHandle.standardError.write(stderr)
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
}
