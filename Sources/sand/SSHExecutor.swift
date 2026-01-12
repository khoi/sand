import Citadel
import Foundation
import NIOCore

struct SSHExecutor {
    func execute(host: String, username: String, password: String, command: String) async throws {
        let deadline = Date().addingTimeInterval(300)
        var lastError: Error?
        while Date() < deadline {
            do {
                var settings = SSHClientSettings(
                    host: host,
                    authenticationMethod: { .passwordBased(username: username, password: password) },
                    hostKeyValidator: .acceptAnything()
                )
                settings.connectTimeout = .seconds(60)
                let client = try await SSHClient.connect(to: settings)
                do {
                    _ = try await client.executeCommand(command, mergeStreams: true, inShell: true)
                    try await client.close()
                    return
                } catch {
                    try? await client.close()
                    throw error
                }
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        throw lastError ?? NSError(domain: "ssh", code: 1)
    }
}
