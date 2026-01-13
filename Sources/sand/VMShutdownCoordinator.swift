import Foundation

final class VMShutdownCoordinator {
    private let lock = NSLock()
    private var activeName: String?
    private var cleanupStarted = false
    private let destroyer: VMDestroyer

    init(destroyer: VMDestroyer) {
        self.destroyer = destroyer
    }

    func activate(name: String) {
        lock.lock()
        activeName = name
        cleanupStarted = false
        lock.unlock()
    }

    func cleanup() {
        lock.lock()
        guard !cleanupStarted, let name = activeName else {
            lock.unlock()
            return
        }
        cleanupStarted = true
        lock.unlock()
        destroyer.destroy(name: name)

        lock.lock()
        activeName = nil
        lock.unlock()
    }
}
