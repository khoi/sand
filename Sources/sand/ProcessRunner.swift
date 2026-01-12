import Foundation

struct ProcessResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

enum ProcessRunnerError: Error {
    case failed(exitCode: Int32, stdout: String, stderr: String, command: [String])
    case invalidCommand
}

protocol ProcessRunning {
    func run(executable: String, arguments: [String], wait: Bool) throws -> ProcessResult?
}

struct SystemProcessRunner: ProcessRunning {
    func run(executable: String, arguments: [String], wait: Bool) throws -> ProcessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        if !wait {
            return nil
        }
        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        let exitCode = process.terminationStatus
        if exitCode != 0 {
            throw ProcessRunnerError.failed(exitCode: exitCode, stdout: stdout, stderr: stderr, command: [executable] + arguments)
        }
        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}
