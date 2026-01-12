import Foundation

struct DependencyChecker {
    static func missingCommands(_ commands: [String]) -> [String] {
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let searchPaths = pathValue.split(separator: ":").map(String.init)
        return commands.filter { !isExecutableOnPath($0, searchPaths: searchPaths) }
    }

    private static func isExecutableOnPath(_ command: String, searchPaths: [String]) -> Bool {
        for path in searchPaths {
            let candidate = (path as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return true
            }
        }
        return false
    }
}
