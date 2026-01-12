import Foundation

enum TartError: Error {
    case emptyIP
}

struct Tart {
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

    func run(name: String) throws {
        _ = try processRunner.run(executable: "tart", arguments: ["run", name, "--no-graphics"], wait: false)
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
