import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

final class ProcessHandle: @unchecked Sendable {
    private let waitBlock: () throws -> ProcessResult
    private let terminateBlock: () -> Void

    init(wait: @escaping () throws -> ProcessResult, terminate: @escaping () -> Void) {
        self.waitBlock = wait
        self.terminateBlock = terminate
    }

    func wait() throws -> ProcessResult {
        try waitBlock()
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
        try process.run()
        return ProcessHandle(
            wait: {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                let exitCode = process.terminationStatus
                if exitCode != 0 {
                    throw ProcessRunnerError.failed(exitCode: exitCode, stdout: stdout, stderr: stderr, command: command)
                }
                return ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
            },
            terminate: {
                process.terminate()
            }
        )
    }
}
