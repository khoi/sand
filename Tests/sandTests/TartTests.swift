import XCTest
@testable import sand

final class MockProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let wait: Bool
    }

    var calls: [Call] = []
    var results: [ProcessResult?] = []
    var startCalls: [Call] = []
    var startResults: [Result<ProcessResult, Error>] = []

    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult? {
        calls.append(Call(executable: executable, arguments: arguments, wait: wait))
        if results.isEmpty {
            return ProcessResult(stdout: "", stderr: "", exitCode: 0)
        }
        return results.removeFirst()
    }

    func start(executable: String, arguments: [String]) throws -> ProcessHandle {
        startCalls.append(Call(executable: executable, arguments: arguments, wait: false))
        let result = startResults.isEmpty ? .success(ProcessResult(stdout: "", stderr: "", exitCode: 0)) : startResults.removeFirst()
        return ProcessHandle(
            waitAsync: {
                try result.get()
            },
            terminate: {}
        )
    }
}

func makeTart(_ runner: ProcessRunning) -> Tart {
    Tart(processRunner: runner, logger: Logger(label: "tart.test", minimumLevel: .info))
}

final class TartTests: XCTestCase {
    func testCloneArgs() async throws {
        let runner = MockProcessRunner()
        let tart = makeTart(runner)
        try await tart.clone(source: "source", name: "ephemeral")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["clone", "source", "ephemeral"], wait: true))
    }

    func testRunArgs() async throws {
        let runner = MockProcessRunner()
        let tart = makeTart(runner)
        try await tart.run(name: "ephemeral")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["run", "ephemeral", "--no-graphics"], wait: false))
    }

    func testRunArgsWithOptions() async throws {
        let runner = MockProcessRunner()
        let tart = makeTart(runner)
        let options = Tart.RunOptions(
            directoryMounts: [
                Tart.DirectoryMount(hostPath: "/tmp/dir", guestFolder: "dir", readOnly: true, tag: "build")
            ],
            noAudio: true,
            noGraphics: false,
            noClipboard: true
        )
        try await tart.run(name: "ephemeral", options: options)
        XCTAssertEqual(runner.calls.first, .init(
            executable: "tart",
            arguments: ["run", "ephemeral", "--no-audio", "--no-clipboard", "--dir", "dir:/tmp/dir:ro,tag=build"],
            wait: false
        ))
    }

    func testSetArgs() async throws {
        let runner = MockProcessRunner()
        let tart = makeTart(runner)
        let display = Tart.Display(width: 1920, height: 1080, unit: "px")
        try await tart.set(name: "ephemeral", cpuCores: 4, memoryMb: 4096, display: display, displayRefit: true, diskSizeGb: 80)
        XCTAssertEqual(runner.calls.first, .init(
            executable: "tart",
            arguments: ["set", "ephemeral", "--cpu", "4", "--memory", "4096", "--display", "1920x1080px", "--display-refit", "--disk-size", "80"],
            wait: true
        ))
    }

    func testIpArgs() async throws {
        let runner = MockProcessRunner()
        runner.results = [ProcessResult(stdout: "10.0.0.1\n", stderr: "", exitCode: 0)]
        let tart = makeTart(runner)
        let ip = try await tart.ip(name: "ephemeral", wait: 60)
        XCTAssertEqual(ip, "10.0.0.1")
        XCTAssertEqual(runner.calls.first, .init(executable: "tart", arguments: ["ip", "ephemeral", "--wait", "60"], wait: true))
    }

    func testPrepareSkipsPullWhenPresent() async throws {
        let runner = MockProcessRunner()
        runner.results = [ProcessResult(stdout: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest\n", stderr: "", exitCode: 0)]
        let tart = makeTart(runner)
        try await tart.prepare(source: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest")
        XCTAssertEqual(runner.calls, [
            .init(executable: "tart", arguments: ["list", "--source", "oci", "--quiet"], wait: true)
        ])
    }

    func testPreparePullsWhenMissing() async throws {
        let runner = MockProcessRunner()
        runner.results = [
            ProcessResult(stdout: "", stderr: "", exitCode: 0),
            ProcessResult(stdout: "", stderr: "", exitCode: 0)
        ]
        let tart = makeTart(runner)
        try await tart.prepare(source: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest")
        XCTAssertEqual(runner.calls, [
            .init(executable: "tart", arguments: ["list", "--source", "oci", "--quiet"], wait: true),
            .init(executable: "tart", arguments: ["pull", "ghcr.io/cirruslabs/macos-tahoe-xcode:latest"], wait: true)
        ])
    }

    func testIsRunningUsesJsonList() async throws {
        let runner = MockProcessRunner()
        runner.results = [
            ProcessResult(stdout: "[{\"Name\":\"vm-1\",\"Running\":true}]", stderr: "", exitCode: 0)
        ]
        let tart = makeTart(runner)
        let running = try await tart.isRunning(name: "vm-1")
        XCTAssertTrue(running)
        XCTAssertEqual(runner.calls, [
            .init(executable: "tart", arguments: ["list", "--format", "json"], wait: true)
        ])
    }

    func testStatusMissingWhenVmNotFound() async throws {
        let runner = MockProcessRunner()
        runner.results = [
            ProcessResult(stdout: "[]", stderr: "", exitCode: 0)
        ]
        let tart = makeTart(runner)
        let status = try await tart.status(name: "missing")
        XCTAssertEqual(status, .missing)
    }

    func testStatusRunningWhenVmIsRunning() async throws {
        let runner = MockProcessRunner()
        runner.results = [
            ProcessResult(stdout: "[{\"Name\":\"vm-1\",\"Running\":true}]", stderr: "", exitCode: 0)
        ]
        let tart = makeTart(runner)
        let status = try await tart.status(name: "vm-1")
        XCTAssertEqual(status, .running)
    }

    func testStatusStoppedWhenVmIsStopped() async throws {
        let runner = MockProcessRunner()
        runner.results = [
            ProcessResult(stdout: "[{\"Name\":\"vm-1\",\"Running\":false}]", stderr: "", exitCode: 0)
        ]
        let tart = makeTart(runner)
        let status = try await tart.status(name: "vm-1")
        XCTAssertEqual(status, .stopped)
    }
}
