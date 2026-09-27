import XCTest
@testable import sand

private actor StopGate {
    private var stopStarted = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private(set) var deleted = false

    func enterStop() async {
        stopStarted = true
        startedWaiters.forEach { $0.resume() }
        startedWaiters = []
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilStopStarted() async {
        if stopStarted {
            return
        }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func markDeleted() {
        deleted = true
    }
}

private struct GatedStopRunner: ProcessRunning {
    let gate: StopGate

    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult? {
        switch arguments.first {
        case "stop":
            await gate.enterStop()
        case "delete":
            await gate.markDeleted()
        default:
            break
        }
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }

    func start(executable: String, arguments: [String]) throws -> ProcessHandle {
        ProcessHandle(waitAsync: { ProcessResult(stdout: "", stderr: "", exitCode: 0) }, terminate: {})
    }
}

final class VMShutdownCoordinatorTests: XCTestCase {
    func testConcurrentCleanupWaitsForInFlightDestroy() async throws {
        let gate = StopGate()
        let logger = Logger(label: "shutdown.test", minimumLevel: .critical)
        let coordinator = VMShutdownCoordinator(
            destroyer: VMDestroyer(tart: makeTart(GatedStopRunner(gate: gate)), logger: logger),
            logger: logger
        )
        await coordinator.activate(name: "vm")
        let first = Task { await coordinator.cleanup(reason: "runner") }
        await gate.waitUntilStopStarted()
        let second = Task {
            await coordinator.cleanup(reason: "signal")
            return await gate.deleted
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await gate.release()
        let deletedBeforeSecondReturned = await second.value
        await first.value
        XCTAssertTrue(deletedBeforeSecondReturned)
    }

    func testCleanupWithoutActiveVMIsNoop() async {
        let gate = StopGate()
        let logger = Logger(label: "shutdown.test", minimumLevel: .critical)
        let coordinator = VMShutdownCoordinator(
            destroyer: VMDestroyer(tart: makeTart(GatedStopRunner(gate: gate)), logger: logger),
            logger: logger
        )
        await coordinator.cleanup(reason: "signal")
        let deleted = await gate.deleted
        XCTAssertFalse(deleted)
    }

    func testCleanupDeregistersAfterDestroyingVM() async {
        let gate = StopGate()
        let logger = Logger(label: "shutdown.test", minimumLevel: .critical)
        let coordinator = VMShutdownCoordinator(
            destroyer: VMDestroyer(tart: makeTart(GatedStopRunner(gate: gate)), logger: logger),
            logger: logger
        )
        let deletedAtDeregistration = DeregistrationProbe()
        await coordinator.activate(name: "vm")
        await coordinator.setDeregistration {
            await deletedAtDeregistration.record(await gate.deleted)
        }
        let cleanup = Task { await coordinator.cleanup(reason: "runner") }
        await gate.waitUntilStopStarted()
        await gate.release()
        await cleanup.value
        let observed = await deletedAtDeregistration.values
        XCTAssertEqual(observed, [true])
    }
}

private actor DeregistrationProbe {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}
