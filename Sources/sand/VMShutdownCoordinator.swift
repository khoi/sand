import Foundation

actor VMShutdownCoordinator {
    private var activeName: String?
    private var cleanupStarted = false
    private let destroyer: VMDestroyer

    init(destroyer: VMDestroyer) {
        self.destroyer = destroyer
    }

    func activate(name: String) {
        activeName = name
        cleanupStarted = false
    }

    func cleanup() async {
        guard !cleanupStarted, let name = activeName else {
            return
        }
        cleanupStarted = true
        try? await destroyer.destroy(name: name)
        activeName = nil
    }
}
