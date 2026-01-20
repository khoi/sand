import XCTest
@testable import sand

final class SSHProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let wait: Bool
    }

    var runCalls: [Call] = []
    var startCalls: [Call] = []

    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult? {
        runCalls.append(Call(executable: executable, arguments: arguments, wait: wait))
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }

    func start(executable: String, arguments: [String]) throws -> ProcessHandle {
        startCalls.append(Call(executable: executable, arguments: arguments, wait: false))
        return ProcessHandle(
            waitAsync: { ProcessResult(stdout: "", stderr: "", exitCode: 0) },
            terminate: {}
        )
    }
}

final class SSHClientTests: XCTestCase {
    func testStartBuildsSSHCommand() async throws {
        let runner = SSHProcessRunner()
        let ssh = SSHClient(
            processRunner: runner,
            host: "10.0.0.1",
            config: .init(user: "admin", password: "pw", port: 2222)
        )
        let handle = try ssh.start(command: "echo hi")
        _ = try await handle.waitAsync()
        let expected = SSHProcessRunner.Call(
            executable: "sshpass",
            arguments: [
                "-p", "pw",
                "ssh",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-p", "2222",
                "admin@10.0.0.1",
                "/bin/bash -lc 'echo hi'"
            ],
            wait: false
        )
        XCTAssertEqual(runner.startCalls.first, expected)
    }
}
