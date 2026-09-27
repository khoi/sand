import Foundation

private final class PipeDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()
    private var finished = false

    init(pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [self] handle in
            lock.withLock {
                guard !finished else {
                    handle.readabilityHandler = nil
                    return
                }
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    data.append(chunk)
                }
            }
        }
    }

    func finish() -> Data {
        handle.readabilityHandler = nil
        return lock.withLock {
            if !finished {
                finished = true
                drainRemaining()
                try? handle.close()
            }
            return data
        }
    }

    private func drainRemaining() {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            return
        }
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else {
                return
            }
            data.append(contentsOf: buffer[0..<count])
        }
    }
}

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

actor ProcessHandle {
    private let process: Process?
    private let stdoutDrain: PipeDrain?
    private let stderrDrain: PipeDrain?
    private let command: [String]?
    private let waitAsyncBlock: (() async throws -> ProcessResult)?
    private let terminateBlock: (() -> Void)?
    private var cachedResult: Result<ProcessResult, Error>?
    private var waiters: [UUID: CheckedContinuation<ProcessResult, Error>] = [:]
    private var terminationHandlerInstalled = false

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe, command: [String]) {
        self.process = process
        self.stdoutDrain = PipeDrain(pipe: stdoutPipe)
        self.stderrDrain = PipeDrain(pipe: stderrPipe)
        self.command = command
        self.waitAsyncBlock = nil
        self.terminateBlock = nil
    }

    init(
        waitAsync: @escaping () async throws -> ProcessResult,
        terminate: @escaping () -> Void
    ) {
        self.process = nil
        self.stdoutDrain = nil
        self.stderrDrain = nil
        self.command = nil
        self.waitAsyncBlock = waitAsync
        self.terminateBlock = terminate
    }

    func waitAsync() async throws -> ProcessResult {
        if let waitAsyncBlock {
            return try await waitAsyncBlock()
        }
        if let cachedResult {
            return try cachedResult.get()
        }
        guard let process else {
            throw ProcessRunnerError.invalidCommand
        }
        if !process.isRunning {
            return try resolveResult().get()
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if let cachedResult {
                    continuation.resume(with: cachedResult)
                    return
                }
                waiters[waiterID] = continuation
                installTerminationHandlerIfNeeded()
                if !process.isRunning {
                    waiters.removeValue(forKey: waiterID)
                    continuation.resume(with: resolveResult())
                }
            }
        }, onCancel: {
            Task { await cancelWaiter(id: waiterID) }
        })
    }

    func terminate() {
        if let terminateBlock {
            terminateBlock()
            return
        }
        guard let process, process.isRunning else {
            return
        }
        process.terminate()
    }

    private func resolveResult() -> Result<ProcessResult, Error> {
        if let cachedResult {
            return cachedResult
        }
        guard let process, let stdoutDrain, let stderrDrain, let command else {
            let failure = Result<ProcessResult, Error>.failure(ProcessRunnerError.invalidCommand)
            cachedResult = failure
            return failure
        }
        let stdoutData = stdoutDrain.finish()
        let stderrData = stderrDrain.finish()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus
        let result: Result<ProcessResult, Error>
        if exitCode != 0 {
            result = .failure(ProcessRunnerError.failed(exitCode: exitCode, stdout: stdout, stderr: stderr, command: command))
        } else {
            result = .success(ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode))
        }
        cachedResult = result
        return result
    }

    private func installTerminationHandlerIfNeeded() {
        guard !terminationHandlerInstalled, let process else {
            return
        }
        terminationHandlerInstalled = true
        process.terminationHandler = { [weak self] _ in
            guard let self else {
                return
            }
            Task { await self.processDidExit() }
        }
    }

    private func processDidExit() {
        let result = resolveResult()
        resumeWaiters(with: result)
    }

    private func resumeWaiters(with result: Result<ProcessResult, Error>) {
        let pending = waiters
        waiters = [:]
        for continuation in pending.values {
            continuation.resume(with: result)
        }
    }

    private func cancelWaiter(id: UUID) {
        if let continuation = waiters.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        }
        if cachedResult == nil, let process, process.isRunning {
            process.terminate()
        }
    }
}

enum ProcessRunnerError: Error, CustomStringConvertible {
    case failed(exitCode: Int32, stdout: String, stderr: String, command: [String])
    case invalidCommand

    var description: String {
        switch self {
        case let .failed(exitCode, _, stderr, command):
            let program = command.first ?? "process"
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "\(program) exited with code \(exitCode)"
            }
            return "\(program) exited with code \(exitCode): \(detail)"
        case .invalidCommand:
            return "invalid command"
        }
    }
}

protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult?
    func start(executable: String, arguments: [String]) throws -> ProcessHandle
}

struct SystemProcessRunner: ProcessRunning, Sendable {
    func run(executable: String, arguments: [String], wait: Bool) async throws -> ProcessResult? {
        let handle = try start(executable: executable, arguments: arguments)
        guard wait else {
            return nil
        }
        return try await handle.waitAsync()
    }

    func start(executable: String, arguments: [String]) throws -> ProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let command = [executable] + arguments
        process.arguments = command
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        return ProcessHandle(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, command: command)
    }
}
