import Foundation

enum TartError: Error {
    case emptyIP
}

struct Tart: Sendable {
    enum VMStatus {
        case missing
        case stopped
        case running
    }
    struct DirectoryMount: Equatable {
        let hostPath: String
        let guestFolder: String
        let readOnly: Bool
        let tag: String?

        var runArgument: String {
            var options: [String] = []
            if readOnly {
                options.append("ro")
            }
            if let tag {
                options.append("tag=\(tag)")
            }
            if options.isEmpty {
                return "\(guestFolder):\(hostPath)"
            }
            return "\(guestFolder):\(hostPath):" + options.joined(separator: ",")
        }
    }

    struct RunOptions {
        let directoryMounts: [DirectoryMount]
        let noAudio: Bool
        let noGraphics: Bool
        let noClipboard: Bool

        static let `default` = RunOptions(directoryMounts: [], noAudio: false, noGraphics: true, noClipboard: false)
    }

    struct Display {
        let width: Int
        let height: Int
        let unit: String?

        var argument: String {
            let suffix = unit.map { $0 } ?? ""
            return "\(width)x\(height)\(suffix)"
        }
    }

    let processRunner: ProcessRunning
    let logger: Logger

    init(processRunner: ProcessRunning, logger: Logger) {
        self.processRunner = processRunner
        self.logger = logger
    }

    func prepare(source: String) async throws {
        if isOCISource(source) {
            if try await hasOCI(source: source) {
                return
            }
            try await pull(source: source)
        }
    }

    func pull(source: String) async throws {
        _ = try await run(arguments: ["pull", source], wait: true)
    }

    func clone(source: String, name: String) async throws {
        _ = try await run(arguments: ["clone", source, name], wait: true)
    }

    func set(
        name: String,
        cpuCores: Int?,
        memoryMb: Int?,
        display: Display?,
        displayRefit: Bool?,
        diskSizeGb: Int?
    ) async throws {
        var arguments = ["set", name]
        if let cpuCores {
            arguments.append(contentsOf: ["--cpu", String(cpuCores)])
        }
        if let memoryMb {
            arguments.append(contentsOf: ["--memory", String(memoryMb)])
        }
        if let display {
            arguments.append(contentsOf: ["--display", display.argument])
        }
        if let displayRefit {
            arguments.append(displayRefit ? "--display-refit" : "--no-display-refit")
        }
        if let diskSizeGb {
            arguments.append(contentsOf: ["--disk-size", String(diskSizeGb)])
        }
        guard arguments.count > 2 else {
            return
        }
        _ = try await run(arguments: arguments, wait: true)
    }

    func run(name: String, options: RunOptions = .default) async throws {
        var arguments = ["run", name]
        if options.noGraphics {
            arguments.append("--no-graphics")
        }
        if options.noAudio {
            arguments.append("--no-audio")
        }
        if options.noClipboard {
            arguments.append("--no-clipboard")
        }
        for mount in options.directoryMounts {
            arguments.append("--dir")
            arguments.append(mount.runArgument)
        }
        _ = try await run(arguments: arguments, wait: false)
    }

    func ip(name: String, wait: Int) async throws -> String {
        let result = try await run(arguments: ["ip", name, "--wait", String(wait)], wait: true)
        let value = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            throw TartError.emptyIP
        }
        return value
    }

    func stop(name: String, timeout: Int? = nil) async throws {
        var arguments = ["stop", name]
        if let timeout {
            arguments.append(contentsOf: ["--timeout", String(timeout)])
        }
        _ = try await run(arguments: arguments, wait: true)
    }

    func delete(name: String) async throws {
        _ = try await run(arguments: ["delete", name], wait: true)
    }

    func isRunning(name: String) async throws -> Bool {
        return try await status(name: name) == .running
    }

    func status(name: String) async throws -> VMStatus {
        let result = try await run(arguments: ["list", "--format", "json"], wait: true)
        let output = result?.stdout ?? ""
        guard let entry = entryFromJSON(output: output, name: name) else {
            return .missing
        }
        if entry.running == true {
            return .running
        }
        return .stopped
    }

    private func isOCISource(_ source: String) -> Bool {
        if source.hasPrefix("file://") {
            return false
        }
        return true
    }

    private func hasOCI(source: String) async throws -> Bool {
        let result = try await run(arguments: ["list", "--source", "oci", "--quiet"], wait: true)
        let output = result?.stdout ?? ""
        let expected = normalizeOCI(source)
        return output
            .split(separator: "\n")
            .map { normalizeOCI(String($0)) }
            .contains(expected)
    }

    private func normalizeOCI(_ source: String) -> String {
        let prefix = "oci://"
        if source.hasPrefix(prefix) {
            return String(source.dropFirst(prefix.count))
        }
        return source
    }

    private struct TartListEntry: Decodable {
        let name: String
        let running: Bool?

        private enum CodingKeys: String, CodingKey {
            case name = "Name"
            case running = "Running"
        }
    }

    private func entryFromJSON(output: String, name: String) -> TartListEntry? {
        guard let data = output.data(using: .utf8) else {
            return nil
        }
        guard let entries = try? JSONDecoder().decode([TartListEntry].self, from: data) else {
            return nil
        }
        return entries.first(where: { $0.name == name })
    }


    private func run(arguments: [String], wait: Bool) async throws -> ProcessResult? {
        logger.debug("tart \(arguments.joined(separator: " "))")
        return try await processRunner.run(executable: "tart", arguments: arguments, wait: wait)
    }
}
