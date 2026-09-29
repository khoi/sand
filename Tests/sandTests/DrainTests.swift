import Foundation
import Testing
import Synchronization
@testable import sand

private func drainConfigPath() throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory.appendingPathComponent("sand.yml").path
}

@Test func drainControlRequestsCompletionAndRejectsDuplicateService() async throws {
    let path = try drainConfigPath()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    let control = try ServiceControl(configPath: path)
    #expect(!control.drainRequested)
    #expect(throws: ServiceControl.ControlError.self) { try ServiceControl(configPath: path) }
    let (paths, instance) = try ServiceControl.requestDrain(configPath: path)
    #expect(control.drainRequested)
    let (_, again) = try ServiceControl.requestDrain(configPath: path)
    #expect(again == instance)
    try control.markDrained()
    try await ServiceControl.waitUntilDrained(paths: paths, instance: instance)
}

@Test func drainControlDoesNotUseStaleRequestsOrCompletion() async throws {
    let path = try drainConfigPath()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    var first: ServiceControl? = try ServiceControl(configPath: path)
    let (paths, oldInstance) = try ServiceControl.requestDrain(configPath: path)
    try first?.markDrained()
    first = nil
    for file in [paths.lock, paths.request, paths.complete] {
        #expect(!FileManager.default.fileExists(atPath: file))
        // Simulate files left behind by an uncatchable termination.
        try oldInstance.write(toFile: file, atomically: true, encoding: .utf8)
    }
    #expect(throws: ServiceControl.ControlError.self) { try ServiceControl.requestDrain(configPath: path) }
    let second = try ServiceControl(configPath: path)
    #expect(!second.drainRequested)
    await #expect(throws: ServiceControl.ControlError.self) {
        try await ServiceControl.waitUntilDrained(paths: paths, instance: oldInstance)
    }
    #expect(second.instance != oldInstance)
    second.cleanup()
    for file in [paths.lock, paths.request, paths.complete] {
        #expect(!FileManager.default.fileExists(atPath: file))
    }
    #expect(throws: ServiceControl.ControlError.self) { try second.markDrained() }
    let third = try ServiceControl(configPath: path)
    second.cleanup() // Repeated cleanup must not remove the replacement instance's files.
    #expect(throws: ServiceControl.ControlError.self) { try ServiceControl(configPath: path) }
    #expect(FileManager.default.fileExists(atPath: third.paths.lock))
}

@Test func drainControlResolvesConfigSymlinks() throws {
    let path = try drainConfigPath()
    defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
    try "runners: []".write(toFile: path, atomically: true, encoding: .utf8)
    let alias = path + ".alias"
    try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: path)
    let control = try ServiceControl(configPath: path)
    _ = try ServiceControl.requestDrain(configPath: alias)
    #expect(control.drainRequested)
}

@Test(arguments: [true, false])
func drainGitHubOnlyRemovesIdleRunners(busy: Bool) async throws {
    let session = MockSession()
    session.responses["/orgs/org/installation"] = (Data(#"{"id":1}"#.utf8), 200)
    session.responses["/app/installations/1/access_tokens"] = (Data(#"{"token":"access"}"#.utf8), 200)
    session.responses["/orgs/org/actions/runners"] = (Data("{\"runners\":[{\"id\":7,\"name\":\"runner\",\"busy\":\(busy)}]}".utf8), 200)
    session.responses["/orgs/org/actions/runners/7"] = (Data(), 204)
    let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: nil)
    let result = try await service.removeRunner(named: "runner", onlyIfIdle: true)
    #expect(result == (busy ? .busy : .removed))
    #expect(session.requests.contains { $0.httpMethod == "DELETE" } == !busy)
}

@Test(arguments: [422, 403, 500])
func drainGitHubHandlesAssignmentRaceAndAPIFailure(status: Int) async throws {
    let session = MockSession()
    session.responses["/repos/org/repo/installation"] = (Data(#"{"id":1}"#.utf8), 200)
    session.responses["/app/installations/1/access_tokens"] = (Data(#"{"token":"access"}"#.utf8), 200)
    session.responses["/repos/org/repo/actions/runners"] = (Data(#"{"runners":[{"id":7,"name":"runner","busy":false}]}"#.utf8), 200)
    session.responses["/repos/org/repo/actions/runners/7"] = (Data("error".utf8), status)
    let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: "repo")
    if status == 422 {
        #expect(try await service.removeRunner(named: "runner", onlyIfIdle: true) == .busy)
    } else {
        await #expect(throws: GitHubServiceError.self) { try await service.removeRunner(named: "runner", onlyIfIdle: true) }
    }
}

@Test(arguments: [#"{"runners":[]}"#, #"{"runners":[{"id":7,"name":"runner"}]}"#])
func drainGitHubDoesNotDeleteUnknownState(payload: String) async throws {
    let session = MockSession()
    session.responses["/orgs/org/installation"] = (Data(#"{"id":1}"#.utf8), 200)
    session.responses["/app/installations/1/access_tokens"] = (Data(#"{"token":"access"}"#.utf8), 200)
    session.responses["/orgs/org/actions/runners"] = (Data(payload.utf8), 200)
    let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: nil)
    #expect(try await service.removeRunner(named: "runner", onlyIfIdle: true) != .removed)
    #expect(!session.requests.contains { $0.httpMethod == "DELETE" })
}

// Real subprocesses exercise cancellation and job completion; VM/SSH transport is simulated.
private final class DrainTestProcessRunner: ProcessRunning, Sendable {
    struct State {
        var exists = false
        var running = false
        var clones = 0
        var vm: ProcessHandle?
        var calls: [[String]] = []
    }
    let state = Synchronization.Mutex(State())
    let system = SystemProcessRunner()

    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult? {
        state.withLock { $0.calls.append(arguments) }
        var stdout = ""
        if executable == "tart" {
            switch arguments.first {
            case "list":
                stdout = state.withLock { $0.exists ? "[{\"Name\":\"drain-test\",\"Running\":\($0.running)}]" : "[]" }
            case "clone":
                state.withLock { $0.exists = true; $0.clones += 1 }
            case "ip": stdout = "127.0.0.1"
            case "stop":
                let vm = state.withLock { $0.running = false; return $0.vm }
                await vm?.terminate()
            case "delete": state.withLock { $0.exists = false }
            default: break
            }
        }
        return ProcessResult(stdout: stdout, stderr: "", exitCode: 0)
    }

    func start(executable: String, arguments: [String]) throws -> ProcessHandle {
        if executable == "tart" {
            let vm = try system.start(executable: "/bin/sleep", arguments: ["30"])
            state.withLock { $0.vm = vm; $0.running = true }
            return vm
        }
        return try system.start(executable: "/bin/sh", arguments: ["-c", arguments.last!])
    }
}

@Test func drainLetsActiveScriptFinishWithoutCreatingAnotherVM() async throws {
    let path = try drainConfigPath()
    let directory = (path as NSString).deletingLastPathComponent
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let control = try ServiceControl(configPath: path)
    let process = DrainTestProcessRunner()
    let tart = makeTart(process)
    let started = directory + "/started"
    let release = directory + "/release"
    let finished = directory + "/finished"
    let quote = GitHubProvisioner.shellQuote
    let script = "touch \(quote(started)); for i in {1..100}; do test -f \(quote(release)) && break; sleep 0.05; done; test -f \(quote(release)) && touch \(quote(finished))"
    let config = Config.RunnerConfig(name: "drain-test", vm: Config.VM(
        source: .init(type: .local, image: nil, name: "source"), hardware: nil,
        mounts: [], cache: nil, run: .default, diskSizeGb: nil, ssh: .standard),
        provisioner: .init(type: .script, script: .init(run: script), github: nil),
        preRun: nil, postRun: "echo post-run", stopAfter: nil, healthCheck: nil)
    let logger = Logger(label: "drain.test", minimumLevel: .critical)
    let runner = Runner(tart: tart, github: nil, provisioner: GitHubProvisioner(),
        runnerVersionResolver: GitHubRunnerVersionResolver(), runnerCache: RunnerCache(), config: config,
        shutdownCoordinator: VMShutdownCoordinator(destroyer: VMDestroyer(tart: tart, logger: logger), logger: logger),
        control: RunnerControl(), vmName: "drain-test", logLabel: "drain-test", logLevel: .critical,
        logSink: nil, serviceControl: control)
    let task = Task { try await runner.run() }
    defer { task.cancel() }
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: started) { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(FileManager.default.fileExists(atPath: started))
    _ = try ServiceControl.requestDrain(configPath: path)
    #expect(process.state.withLock { $0.running })
    #expect(!FileManager.default.fileExists(atPath: finished))
    try Data().write(to: URL(fileURLWithPath: release))
    try await task.value
    #expect(FileManager.default.fileExists(atPath: finished))
    #expect(process.state.withLock { $0.clones == 1 && !$0.exists })
    #expect(process.state.withLock { $0.calls.contains { $0.last?.contains("echo post-run") == true } })
}
