import Foundation
import Synchronization
import Testing
@testable import sand

private actor ImageProcessRunner: ProcessRunning {
    enum Failure: Error { case pull }
    private(set) var calls: [[String]] = []
    private(set) var overlapped = false
    private var active = false
    private var cached: Bool
    private var failPull = false

    init(cached: Bool = true) { self.cached = cached }

    func setFailure(cached: Bool) {
        failPull = true
        self.cached = cached
    }

    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult? {
        if active { overlapped = true }
        active = true
        defer { active = false }
        calls.append(arguments)
        for _ in 0..<20 { await Task.yield() }
        if arguments.first == "pull" {
            if failPull { throw Failure.pull }
            cached = true
        }
        return ProcessResult(stdout: cached ? "registry/vm:latest\nregistry/other:latest\n" : "", stderr: "", exitCode: 0)
    }

    nonisolated func start(executable: String, arguments: [String]) throws -> ProcessHandle {
        throw ProcessRunnerError.invalidCommand
    }
}

private let imageSource = Config.VMSource(type: .oci, image: "registry/vm:latest", name: nil)

@Test func imageRefreshScheduleAndRetry() async throws {
    let time = Mutex(Date(timeIntervalSince1970: 0))
    let coordinator = ImageRefreshCoordinator(intervalSeconds: 86400, now: { time.withLock { $0 } })
    let process = ImageProcessRunner()
    let tart = makeTart(process)
    try await coordinator.clone(tart: tart, source: imageSource, name: "first")
    time.withLock { $0 = Date(timeIntervalSince1970: 86_399) }
    try await coordinator.clone(tart: tart, source: imageSource, name: "before-due")
    #expect(await process.calls.filter { $0.first == "pull" }.count == 1)
    time.withLock { $0 = Date(timeIntervalSince1970: 86_400) }
    try await coordinator.clone(tart: tart, source: imageSource, name: "due")
    #expect(await process.calls.filter { $0.first == "pull" }.count == 2)

    await process.setFailure(cached: true)
    time.withLock { $0 = Date(timeIntervalSince1970: 172_800) }
    try await coordinator.clone(tart: tart, source: imageSource, name: "fallback")
    time.withLock { $0 = Date(timeIntervalSince1970: 173_099) }
    try await coordinator.clone(tart: tart, source: imageSource, name: "before-retry")
    #expect(await process.calls.filter { $0.first == "pull" }.count == 3)
    time.withLock { $0 = Date(timeIntervalSince1970: 173_100) }
    try await coordinator.clone(tart: tart, source: imageSource, name: "retry")
    #expect(await process.calls.filter { $0.first == "pull" }.count == 4)
}

@Test func imageRefreshSerializesRunnersAndSharesSchedule() async throws {
    let coordinator = ImageRefreshCoordinator(intervalSeconds: 86400)
    let process = ImageProcessRunner()
    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 0..<12 {
            group.addTask {
                let source = index % 2 == 0 ? imageSource : Config.VMSource(type: .oci, image: "registry/other:latest", name: nil)
                try await coordinator.clone(tart: makeTart(process), source: source, name: "vm-\(index)")
            }
        }
        try await group.waitForAll()
    }
    #expect(await process.overlapped == false)
    #expect(await process.calls.filter { $0.first == "pull" }.count == 2)
    #expect(await process.calls.filter { $0.first == "clone" }.count == 12)
}

@Test func imageRefreshFailureWithoutCacheDoesNotCloneAndReleasesGate() async throws {
    let coordinator = ImageRefreshCoordinator(intervalSeconds: 86400)
    let process = ImageProcessRunner()
    await process.setFailure(cached: false)
    await #expect(throws: ImageProcessRunner.Failure.self) {
        try await coordinator.clone(tart: makeTart(process), source: imageSource, name: "missing")
    }
    #expect(await process.calls.filter { $0.first == "clone" }.isEmpty)
    let local = Config.VMSource(type: .local, image: nil, name: "local-vm")
    try await coordinator.clone(tart: makeTart(process), source: local, name: "local-copy")
    #expect(await process.calls.last == ["clone", "local-vm", "local-copy"])
}

@Test func disabledImageRefreshOnlyPullsMissingImages() async throws {
    let coordinator = ImageRefreshCoordinator()
    let process = ImageProcessRunner(cached: false)
    for name in ["first", "second"] {
        try await coordinator.clone(tart: makeTart(process), source: imageSource, name: name)
    }
    #expect(await process.calls.filter { $0.first == "pull" }.count == 1)
}

@Test func imageRefreshRepullsEvictedCacheBeforeIntervalExpires() async throws {
    let coordinator = ImageRefreshCoordinator(intervalSeconds: 86400)
    try await coordinator.clone(tart: makeTart(ImageProcessRunner()), source: imageSource, name: "first")
    let emptyCache = ImageProcessRunner(cached: false)
    try await coordinator.clone(tart: makeTart(emptyCache), source: imageSource, name: "second")
    #expect(await emptyCache.calls.contains(["pull", "registry/vm:latest"]))
}

@Test func imageRefreshConfigSurvivesPathExpansion() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let full = try Config.load(path: root.appendingPathComponent("fixtures/sample_full_config.yml").path)
    #expect(full.imageRefreshIntervalSeconds == 86400)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yml")
    defer { try? FileManager.default.removeItem(at: file) }
    try "runners: []\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(try Config.load(path: file.path).imageRefreshIntervalSeconds == nil)
}

@Test(arguments: [0.0, -1, Double.infinity, Double.nan, -Double.infinity])
func imageRefreshRejectsInvalidIntervals(seconds: Double) {
    let config = Config(runners: [], imageRefreshIntervalSeconds: seconds)
    #expect(ConfigValidator().validate(config).contains {
        $0.severity == .error && $0.message.contains("imageRefreshIntervalSeconds")
    })
}

@Test func cancelledImageRefreshDoesNotRunCommandsAndReleasesGate() async throws {
    let coordinator = ImageRefreshCoordinator(intervalSeconds: 86400)
    let process = ImageProcessRunner()
    let cancelled = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        try await coordinator.clone(tart: makeTart(process), source: imageSource, name: "cancelled")
    }
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    #expect(await process.calls.isEmpty)
    try await coordinator.clone(tart: makeTart(process), source: imageSource, name: "next")
    #expect(await process.calls.last == ["clone", "registry/vm:latest", "next"])
}
