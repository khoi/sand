import Foundation

struct VMDestroyer {
    let tart: Tart
    let logger: Logger

    func destroy(name: String) throws {
        for attempt in 1...3 {
            logger.info("stop VM \(name) (attempt \(attempt))")
            do {
                try tart.stop(name: name)
            } catch {
                logger.warning("failed to stop VM \(name): \(String(describing: error))")
            }
            _ = waitForStatus(name: name, acceptable: [.stopped, .missing], timeout: 10)
            logger.info("delete VM \(name) (attempt \(attempt))")
            do {
                try tart.delete(name: name)
            } catch {
                logger.warning("failed to delete VM \(name): \(String(describing: error))")
            }
            if waitForStatus(name: name, acceptable: [.missing], timeout: 10) {
                return
            }
        }
        logger.warning("VM \(name) still present after delete attempts")
    }

    private func waitForStatus(
        name: String,
        acceptable: [Tart.VMStatus],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let status = try? tart.status(name: name), acceptable.contains(status) {
                return true
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }
}
