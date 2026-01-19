import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

final class ProcessHandle: @unchecked Sendable {
    private let waitBlock: () throws -> ProcessResult
    private let waitAsyncBlock: () async throws -> ProcessResult
    private let terminateBlock: () -> Void

    init(
        wait: @escaping () throws -> ProcessResult,
        waitAsync: @escaping () async throws -> ProcessResult,
        terminate: @escaping () -> Void
    ) {
        self.waitBlock = wait
        self.waitAsyncBlock = waitAsync
        self.terminateBlock = terminate
    }

    func wait() throws -> ProcessResult {
        try waitBlock()
    }

    func waitAsync() async throws -> ProcessResult {
        try await waitAsyncBlock()
    }

    func terminate() {
        terminateBlock()
    }
}

enum ProcessRunnerError: Error {
    case failed(exitCode: Int32, stdout: String, stderr: String, command: [String])
    case invalidCommand
}

protocol ProcessRunning {
    func run(executable: String, arguments: [String], wait: Bool) throws -> ProcessResult?
    func start(executable: String, arguments: [String]) throws -> ProcessHandle
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String], wait: Bool) throws -> ProcessResult? {
        let handle = try start(executable: executable, arguments: arguments)
        guard wait else {
            return nil
        }
        return try handle.wait()
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
        final class WaitContext: @unchecked Sendable {
            private let lock = NSLock()
            private var cachedResult: Result<ProcessResult, Error>?
            private let process: Process
            private let stdoutPipe: Pipe
            private let stderrPipe: Pipe
            private let command: [String]

            init(process: Process, stdoutPipe: Pipe, stderrPipe: Pipe, command: [String]) {
                self.process = process
                self.stdoutPipe = stdoutPipe
                self.stderrPipe = stderrPipe
                self.command = command
            }

            func resolveResult() -> Result<ProcessResult, Error> {
                lock.lock()
                if let cachedResult {
                    lock.unlock()
                    return cachedResult
                }
                lock.unlock()

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

                lock.lock()
                cachedResult = result
                lock.unlock()
                return result
            }
        }

        let context = WaitContext(process: process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, command: command)

        try process.run()
        return ProcessHandle(
            wait: {
                process.waitUntilExit()
                return try context.resolveResult().get()
            },
            waitAsync: {
                final class AsyncWaitState: @unchecked Sendable {
                    private let lock = NSLock()
                    private var continuation: CheckedContinuation<ProcessResult, Error>?
                    private var resolved = false

                    func setContinuation(_ continuation: CheckedContinuation<ProcessResult, Error>) {
                        lock.lock()
                        self.continuation = continuation
                        lock.unlock()
                    }

                    func resume(_ result: Result<ProcessResult, Error>) {
                        lock.lock()
                        guard !resolved, let continuation else {
                            lock.unlock()
                            return
                        }
                        resolved = true
                        self.continuation = nil
                        lock.unlock()
                        continuation.resume(with: result)
                    }
                }

                let state = AsyncWaitState()
                return try await withTaskCancellationHandler(operation: {
                    try await withCheckedThrowingContinuation { continuation in
                        state.setContinuation(continuation)
                        if !process.isRunning {
                            state.resume(context.resolveResult())
                            return
                        }
                        process.terminationHandler = { _ in
                            state.resume(context.resolveResult())
                        }
                    }
                }, onCancel: {
                    if process.isRunning {
                        process.terminate()
                    }
                    state.resume(.failure(CancellationError()))
                })
            },
            terminate: {
                process.terminate()
            }
        )
    }
}
