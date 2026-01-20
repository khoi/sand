import Foundation

enum LogFileError: Error {
    case openFailed(String)
}

actor LogFileSink {
    private let handle: FileHandle
    private let dateFormatter: ISO8601DateFormatter

    init(path: String) throws {
        let expandedPath = Config.expandPath(path)
        let url = URL(fileURLWithPath: expandedPath)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: expandedPath) {
            FileManager.default.createFile(atPath: expandedPath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: expandedPath) else {
            throw LogFileError.openFailed("Failed to open log file at \(expandedPath)")
        }
        self.handle = handle
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = formatter
        try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    func write(level: LogLevel, label: String, message: String) {
        let normalized = message.replacingOccurrences(of: "\n", with: "\\n")
        let timestamp = dateFormatter.string(from: Date())
        let line = "\(timestamp) [\(level.rawValue)] \(label) \(normalized)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        handle.write(data)
    }

    nonisolated func writeSync(level: LogLevel, label: String, message: String) {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await self.write(level: level, label: label, message: message)
            semaphore.signal()
        }
        semaphore.wait()
    }
}
