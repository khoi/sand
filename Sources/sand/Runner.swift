import Foundation
import OSLog

struct Runner {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let ssh: SSHExecutor
    let config: Config
    private let logger = Logger(subsystem: "sand", category: "runner")

    enum RunnerError: Error {
        case missingGitHub
        case missingScript
    }

    func run() async throws {
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
            let result = try tart.exec(name: name, command: run)
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
            try await ssh.execute(host: ip, username: config.ssh.username, password: config.ssh.password, command: script)
            logger.info("github provisioner finished")
        }
    }
}
