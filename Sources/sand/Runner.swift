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
        try tart.prepare(source: config.source)
        try tart.clone(source: config.source, name: name)
        defer {
            try? tart.delete(name: name)
        }
        try tart.run(name: name)
        defer {
            try? tart.stop(name: name)
        }
        let ip = try tart.ip(name: name, wait: 60)
        switch config.provisioner.type {
        case .script:
            guard let run = config.provisioner.script?.run else {
                throw RunnerError.missingScript
            }
            try tart.exec(name: name, command: run)
        case .github:
            guard let github, let githubConfig = config.provisioner.github else {
                throw RunnerError.missingGitHub
            }
            let token = try await github.runnerRegistrationToken()
            let downloadURL = try await github.runnerDownloadURL()
            let script = provisioner.script(config: githubConfig, runnerToken: token, downloadURL: downloadURL)
            try await ssh.execute(host: ip, username: config.ssh.username, password: config.ssh.password, command: script)
        }
    }
}
