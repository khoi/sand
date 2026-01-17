import Foundation

enum LogFileError: Error {
    case openFailed(String)
}

final class LogFileSink: @unchecked Sendable {
    private let lock = NSLock()
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
        let timestamp = dateFormatter.string(from: Date())
        let normalized = message.replacingOccurrences(of: "\n", with: "\\n")
        let line = "\(timestamp) [\(level.rawValue)] \(label) \(normalized)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        lock.lock()
        handle.write(data)
        lock.unlock()
    }
}
