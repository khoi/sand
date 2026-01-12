import Foundation

struct Runner {
    let tart: Tart
    let github: GitHubService?
    let provisioner: GitHubProvisioner
    let ssh: SSHExecutor
    let config: Config

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
        info("prepare source \(config.source)")
        try tart.prepare(source: config.source)
        info("clone VM \(name) from \(config.source)")
        try tart.clone(source: config.source, name: name)
        defer {
            info("delete VM \(name)")
            try? tart.delete(name: name)
        }
        info("boot VM \(name)")
        try tart.run(name: name)
        defer {
            info("stop VM \(name)")
            try? tart.stop(name: name)
        }
        info("wait for VM IP")
        let ip = try tart.ip(name: name, wait: 60)
        info("VM IP \(ip)")
        switch config.provisioner.type {
        case .script:
            guard let run = config.provisioner.script?.run else {
                throw RunnerError.missingScript
            }
            info("run script provisioner")
            let result = try tart.exec(name: name, command: run)
            if let stdout = result?.stdout.data(using: .utf8) {
                FileHandle.standardOutput.write(stdout)
            }
            if let stderr = result?.stderr.data(using: .utf8) {
                FileHandle.standardError.write(stderr)
            }
            info("script provisioner finished")
        case .github:
            guard let github, let githubConfig = config.provisioner.github else {
                throw RunnerError.missingGitHub
            }
            info("run github provisioner")
            let token = try await github.runnerRegistrationToken()
            let downloadURL = try await github.runnerDownloadURL()
            let script = provisioner.script(config: githubConfig, runnerToken: token, downloadURL: downloadURL)
            try await ssh.execute(host: ip, username: config.ssh.username, password: config.ssh.password, command: script)
            info("github provisioner finished")
        }
    }

    private func info(_ message: String) {
        print("[INFO] \(message)")
    }
}
