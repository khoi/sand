import XCTest
@testable import sand

final class ProcessRunnerTests: XCTestCase {
    func testFailedErrorDescriptionOmitsArguments() {
        let error = ProcessRunnerError.failed(
            exitCode: 255,
            stdout: "",
            stderr: "ssh: connect to host 10.0.0.1 port 22: Connection refused\n",
            command: ["sshpass", "-p", "hunter2", "ssh", "admin@10.0.0.1", "config.sh --token SECRET"]
        )
        let description = String(describing: error)
        XCTAssertEqual(description, "sshpass exited with code 255: ssh: connect to host 10.0.0.1 port 22: Connection refused")
        XCTAssertFalse(description.contains("hunter2"))
        XCTAssertFalse(description.contains("SECRET"))
    }

    func testFailedErrorDescriptionWithoutStderr() {
        let error = ProcessRunnerError.failed(exitCode: 1, stdout: "out", stderr: " \n", command: ["tart", "clone", "a", "b"])
        XCTAssertEqual(String(describing: error), "tart exited with code 1")
    }

    func testRedactReplacesSecrets() {
        let command = "~/actions-runner/config.sh --url https://github.com/org --token ABC123 --ephemeral"
        let redacted = Runner.redact(command, secrets: ["ABC123", ""])
        XCTAssertEqual(redacted, "~/actions-runner/config.sh --url https://github.com/org --token [REDACTED] --ephemeral")
    }

    func testWaitCollectsOutputLargerThanPipeBuffer() async throws {
        let result = try await withTimeout(seconds: 10) {
            try await SystemProcessRunner().run(
                executable: "sh",
                arguments: ["-c", "head -c 200000 /dev/zero | tr '\\0' a; head -c 100000 /dev/zero | tr '\\0' b >&2"],
                wait: true
            )
        }
        XCTAssertEqual(result?.stdout.count, 200_000)
        XCTAssertEqual(result?.stderr.count, 100_000)
    }

    func testDetachedProcessIsNotBlockedByUnreadOutput() async throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        defer { try? FileManager.default.removeItem(atPath: marker) }
        _ = try await SystemProcessRunner().run(
            executable: "sh",
            arguments: ["-c", "head -c 200000 /dev/zero; head -c 200000 /dev/zero >&2; touch '\(marker)'"],
            wait: false
        )
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: marker), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker))
    }

    private func withTimeout<T: Sendable>(
        seconds: UInt64,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            defer { group.cancelAll() }
            guard let result = try await group.next(), let value = result else {
                throw CancellationError()
            }
            return value
        }
    }
}
