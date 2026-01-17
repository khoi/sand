import Foundation

struct SSHClient {
    let processRunner: ProcessRunning
    let host: String
    let config: Config.SSH

    func exec(command: String) throws -> ProcessResult? {
        let escaped = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "/bin/bash -lc '\(escaped)'"
        return try processRunner.run(
            executable: "sshpass",
            arguments: [
                "-p", config.password,
                "ssh",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", String(config.port),
                "\(config.user)@\(host)",
                remote
            ],
            wait: true
        )
    }

    func start(command: String) throws -> ProcessHandle {
        let escaped = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "/bin/bash -lc '\(escaped)'"
        return try processRunner.start(
            executable: "sshpass",
            arguments: [
                "-p", config.password,
                "ssh",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", String(config.port),
                "\(config.user)@\(host)",
                remote
            ]
        )
    }

    func checkConnection() throws {
        _ = try exec(command: "true")
    }
}
