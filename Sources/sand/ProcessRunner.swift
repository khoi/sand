import Foundation

struct ProcessResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

actor ProcessHandle {
    private let process: Process?
    private let stdoutPipe: Pipe?
    private let stderrPipe: Pipe?
    private let command: [String]?
    private let waitAsyncBlock: (() async throws -> ProcessResult)?
    private let terminateBlock: (() -> Void)?
    private var cachedResult: Result<ProcessResult, Error>?
    private var waiters: [UUID: CheckedContinuation<ProcessResult, Error>] = [:]
    private var terminationHandlerInstalled = false

    init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe, command: [String]) {
        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.command = command
        self.waitAsyncBlock = nil
        self.terminateBlock = nil
    }

    init(
        waitAsync: @escaping () async throws -> ProcessResult,
        terminate: @escaping () -> Void
    ) {
        self.process = nil
        self.stdoutPipe = nil
        self.stderrPipe = nil
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
        guard let process, let stdoutPipe, let stderrPipe, let command else {
            let failure = Result<ProcessResult, Error>.failure(ProcessRunnerError.invalidCommand)
            cachedResult = failure
            return failure
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
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

enum ProcessRunnerError: Error {
    case failed(exitCode: Int32, stdout: String, stderr: String, command: [String])
    case invalidCommand
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
