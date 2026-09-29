import Darwin
import Foundation
import Synchronization

/// A config-specific lock and request file avoid PID reuse and signalling the wrong process.
final class ServiceControl: Sendable {
    struct Paths: Sendable {
        let lock: String
        let request: String
        let complete: String

        init(configPath: String) {
            let config = URL(fileURLWithPath: Config.expandPath(configPath)).standardizedFileURL.resolvingSymlinksInPath().path
            lock = config + ".sand-lock"
            request = config + ".sand-drain"
            complete = config + ".sand-drained"
        }
    }

    enum ControlError: Error, CustomStringConvertible {
        case alreadyRunning, notRunning, serviceStopped, system(String)

        var description: String {
            switch self {
            case .alreadyRunning: "sand is already running with this configuration."
            case .notRunning: "No running sand service found for this configuration."
            case .serviceStopped: "sand stopped or restarted before drain completion."
            case let .system(message): message
            }
        }
    }

    let paths: Paths
    let instance: String
    private let descriptor: Int32
    private let stopped = Mutex(false)

    init(configPath: String) throws {
        paths = Paths(configPath: configPath)
        instance = UUID().uuidString
        var fd: Int32
        while true {
            fd = open(paths.lock, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw ControlError.system(String(cString: strerror(errno))) }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
                close(fd)
                throw ControlError.alreadyRunning
            }
            // Shutdown may have unlinked this inode after we opened it.
            var opened = stat()
            var current = stat()
            if fstat(fd, &opened) == 0, lstat(paths.lock, &current) == 0,
               opened.st_dev == current.st_dev, opened.st_ino == current.st_ino { break }
            close(fd)
        }
        let bytes = Array(instance.utf8)
        guard ftruncate(fd, 0) == 0,
              bytes.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == bytes.count else {
            let message = String(cString: strerror(errno))
            unlink(paths.lock)
            close(fd)
            throw ControlError.system(message)
        }
        do {
            // Clients only open this existing file, so a late request cannot recreate it after shutdown.
            try Self.write("", to: paths.request)
        } catch {
            unlink(paths.lock)
            close(fd)
            throw error
        }
        descriptor = fd
    }

    deinit { cleanup() }

    func cleanup() {
        stopped.withLock { stopped in
            guard !stopped else { return }
            stopped = true
            unlink(paths.request)
            unlink(paths.complete)
            // Remove the lock last, while we still own it.
            unlink(paths.lock)
            close(descriptor)
        }
    }

    var drainRequested: Bool {
        (try? String(contentsOfFile: paths.request, encoding: .utf8)) == instance
    }

    func markDrained() throws {
        try stopped.withLock { stopped in
            guard !stopped else { throw ControlError.serviceStopped }
            try Self.write(instance, to: paths.complete)
        }
    }

    static func requestDrain(configPath: String) throws -> (Paths, String) {
        let paths = Paths(configPath: configPath)
        guard isRunning(paths) else { throw ControlError.notRunning }
        let instance = try String(contentsOfFile: paths.lock, encoding: .utf8)
        guard !instance.isEmpty else { throw ControlError.notRunning }
        let request = open(paths.request, O_WRONLY | O_NOFOLLOW | O_CLOEXEC)
        guard request >= 0 else { throw ControlError.serviceStopped }
        defer { close(request) }
        guard isRunning(paths),
              (try? String(contentsOfFile: paths.lock, encoding: .utf8)) == instance else {
            throw ControlError.serviceStopped
        }
        let bytes = Array(instance.utf8)
        guard bytes.withUnsafeBytes({ pwrite(request, $0.baseAddress, $0.count, 0) }) == bytes.count else {
            throw ControlError.system(String(cString: strerror(errno)))
        }
        return (paths, instance)
    }

    static func waitUntilDrained(paths: Paths, instance: String) async throws {
        while true {
            guard isRunning(paths),
                  (try? String(contentsOfFile: paths.lock, encoding: .utf8)) == instance else {
                throw ControlError.serviceStopped
            }
            if (try? String(contentsOfFile: paths.complete, encoding: .utf8)) == instance { return }
            try await Task.sleep(for: .seconds(1))
        }
    }

    private static func isRunning(_ paths: Paths) -> Bool {
        let descriptor = open(paths.lock, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return false }
        return errno == EWOULDBLOCK
    }

    private static func write(_ value: String, to path: String) throws {
        try value.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
