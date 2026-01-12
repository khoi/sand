import Foundation
import Logging

final class VMShutdownCoordinator {
    private let lock = NSLock()
    private var activeName: String?
    private var cleanupStarted = false
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func activate(name: String) {
        lock.lock()
        activeName = name
        cleanupStarted = false
        lock.unlock()
    }

    func cleanup(tart: Tart) {
        lock.lock()
        guard !cleanupStarted, let name = activeName else {
            lock.unlock()
            return
        }
        cleanupStarted = true
        lock.unlock()

        logger.info("stop VM \(name)")
        try? tart.stop(name: name)
        logger.info("delete VM \(name)")
        try? tart.delete(name: name)

        lock.lock()
        activeName = nil
        lock.unlock()
    }
}
