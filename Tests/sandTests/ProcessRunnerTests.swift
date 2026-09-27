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
}
