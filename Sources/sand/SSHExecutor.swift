import Citadel
import Foundation

struct SSHExecutor {
    func execute(host: String, username: String, password: String, command: String) async throws {
        let settings = SSHClientSettings(
            host: host,
            authenticationMethod: { .passwordBased(username: username, password: password) },
            hostKeyValidator: .acceptAnything()
        )
        let client = try await SSHClient.connect(to: settings)
        _ = try await client.executeCommand(command, mergeStreams: true, inShell: true)
        try await client.close()
    }
}
