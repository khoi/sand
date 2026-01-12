import XCTest
@testable import sand

final class TartTests: XCTestCase {
    final class MockProcessRunner: ProcessRunning {
        struct Call: Equatable {
            let executable: String
            let arguments: [String]
            let wait: Bool
        }

        var calls: [Call] = []
        var results: [ProcessResult?] = []

        func run(executable: String, arguments: [String], wait: Bool) throws -> ProcessResult? {
            calls.append(Call(executable: executable, arguments: arguments, wait: wait))
            if results.isEmpty {
                return ProcessResult(stdout: "", stderr: "", exitCode: 0)
            }
            return results.removeFirst()
        }
    }

    func testCloneArgs() throws {
        let runner = MockProcessRunner()
        let tart = Tart(processRunner: runner)
        try tart.clone(source: "source", name: "ephemeral")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["clone", "source", "ephemeral"], wait: true))
    }

    func testRunArgs() throws {
        let runner = MockProcessRunner()
        let tart = Tart(processRunner: runner)
        try tart.run(name: "ephemeral")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["run", "ephemeral", "--no-graphics"], wait: false))
    }

    func testRunArgsWithOptions() throws {
        let runner = MockProcessRunner()
        let tart = Tart(processRunner: runner)
        let options = Tart.RunOptions(
            directoryMounts: [
                Tart.DirectoryMount(hostPath: "/tmp/dir", guestFolder: "dir", readOnly: true)
            ],
            noAudio: true
        )
        try tart.run(name: "ephemeral", options: options)
        XCTAssertEqual(runner.calls.first, .init(
            executable: "tart",
            arguments: ["run", "ephemeral", "--no-graphics", "--no-audio", "--dir", "dir:/tmp/dir:ro"],
            wait: false
        ))
    }

    func testSetArgs() throws {
        let runner = MockProcessRunner()
        let tart = Tart(processRunner: runner)
        let display = Tart.Display(width: 1920, height: 1080, unit: "px")
        try tart.set(name: "ephemeral", cpuCores: 4, memoryMb: 4096, display: display)
        XCTAssertEqual(runner.calls.first, .init(
            executable: "tart",
            arguments: ["set", "ephemeral", "--cpu", "4", "--memory", "4096", "--display", "1920x1080px"],
            wait: true
        ))
    }

    func testIPArgs() throws {
        let runner = MockProcessRunner()
        runner.results = [ProcessResult(stdout: "10.0.0.1\n", stderr: "", exitCode: 0)]
        let tart = Tart(processRunner: runner)
        let ip = try tart.ip(name: "ephemeral", wait: 60)
        XCTAssertEqual(ip, "10.0.0.1")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["ip", "ephemeral", "--wait", "60"], wait: true))
    }

    func testPrepareSkipsPullWhenPresent() throws {
        let runner = MockProcessRunner()
        runner.results = [ProcessResult(stdout: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest\n", stderr: "", exitCode: 0)]
        let tart = Tart(processRunner: runner)
        try tart.prepare(source: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest")
        XCTAssertEqual(runner.calls, [
            .init(executable: "tart", arguments: ["list", "--source", "oci", "--quiet"], wait: true)
        ])
    }

    func testPreparePullsWhenMissing() throws {
        let runner = MockProcessRunner()
        runner.results = [
            ProcessResult(stdout: "", stderr: "", exitCode: 0),
            ProcessResult(stdout: "", stderr: "", exitCode: 0)
        ]
        let tart = Tart(processRunner: runner)
        try tart.prepare(source: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest")
        XCTAssertEqual(runner.calls, [
            .init(executable: "tart", arguments: ["list", "--source", "oci", "--quiet"], wait: true),
            .init(executable: "tart", arguments: ["pull", "ghcr.io/cirruslabs/macos-tahoe-xcode:latest"], wait: true)
        ])
    }

    func testExecArgs() throws {
        let runner = MockProcessRunner()
        let tart = Tart(processRunner: runner)
        _ = try tart.exec(name: "ephemeral", command: "echo 1")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["exec", "ephemeral", "/bin/bash", "-lc", "echo 1"], wait: true))
    }
}
