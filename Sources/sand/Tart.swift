import Foundation

enum TartError: Error {
    case emptyIP
}

struct Tart {
    struct DirectoryMount: Equatable {
        let hostPath: String
        let guestFolder: String
        let readOnly: Bool

        var runArgument: String {
            var value = "\(guestFolder):\(hostPath)"
            if readOnly {
                value += ":ro"
            }
            return value
        }
    }

    struct RunOptions {
        let directoryMounts: [DirectoryMount]
        let noAudio: Bool

        static let `default` = RunOptions(directoryMounts: [], noAudio: false)
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

    init(processRunner: ProcessRunning) {
        self.processRunner = processRunner
    }

    func prepare(source: String) throws {
        if isOCISource(source) {
            if try hasOCI(source: source) {
                return
            }
            try pull(source: source)
        }
    }

    func pull(source: String) throws {
        _ = try processRunner.run(executable: "tart", arguments: ["pull", source], wait: true)
    }

    func clone(source: String, name: String) throws {
        _ = try processRunner.run(executable: "tart", arguments: ["clone", source, name], wait: true)
    }

    func set(name: String, cpuCores: Int?, memoryMb: Int?, display: Display?) throws {
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
        guard arguments.count > 2 else {
            return
        }
        _ = try processRunner.run(executable: "tart", arguments: arguments, wait: true)
    }

    func run(name: String, options: RunOptions = .default) throws {
        var arguments = ["run", name, "--no-graphics"]
        if options.noAudio {
            arguments.append("--no-audio")
        }
        for mount in options.directoryMounts {
            arguments.append("--dir")
            arguments.append(mount.runArgument)
        }
        _ = try processRunner.run(executable: "tart", arguments: arguments, wait: false)
    }

    func ip(name: String, wait: Int) throws -> String {
        let result = try processRunner.run(executable: "tart", arguments: ["ip", name, "--wait", String(wait)], wait: true)
        let value = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty {
            throw TartError.emptyIP
        }
        return value
    }

    func stop(name: String) throws {
        _ = try processRunner.run(executable: "tart", arguments: ["stop", name], wait: true)
    }

    func delete(name: String) throws {
        _ = try processRunner.run(executable: "tart", arguments: ["delete", name], wait: true)
    }

    func exec(name: String, command: String) throws -> ProcessResult? {
        return try processRunner.run(executable: "tart", arguments: ["exec", name, "/bin/bash", "-lc", command], wait: true)
    }

    private func isOCISource(_ source: String) -> Bool {
        if source.hasPrefix("file://") {
            return false
        }
        return true
    }

    private func hasOCI(source: String) throws -> Bool {
        let result = try processRunner.run(executable: "tart", arguments: ["list", "--source", "oci", "--quiet"], wait: true)
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
}
