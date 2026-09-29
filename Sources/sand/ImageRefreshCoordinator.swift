import Foundation

actor ImageRefreshCoordinator {
    private let interval: TimeInterval?
    private let now: @Sendable () -> Date
    private var nextRefresh: [String: Date] = [:]
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(intervalSeconds: Double? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        interval = intervalSeconds
        self.now = now
    }

    func clone(tart: Tart, source: Config.VMSource, name: String) async throws {
        // Serialize across images too: Tart's pruning can remove other cached images.
        // The gate stays held across awaits, since actor isolation alone is reentrant.
        if busy {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiters.isEmpty {
                busy = false
            } else {
                waiters.removeFirst().resume()
            }
        }
        try Task.checkCancellation()
        let image = source.resolvedSource
        if source.type == .oci {
            if let interval {
                try await refreshIfDue(tart: tart, image: image, interval: interval)
            } else {
                try await tart.prepare(source: image)
            }
        }
        try Task.checkCancellation()
        try await tart.clone(source: image, name: name)
    }

    private func refreshIfDue(tart: Tart, image: String, interval: TimeInterval) async throws {
        let key = image.hasPrefix("oci://") ? String(image.dropFirst(6)) : image
        if let due = nextRefresh[key], now() < due, try await tart.hasOCI(source: image) {
            return
        }
        tart.logger.info("refresh image \(image)")
        do {
            try await tart.pull(source: image)
            nextRefresh[key] = now().addingTimeInterval(interval)
        } catch {
            try Task.checkCancellation()
            // A failed pull may have pruned the old cache, so verify it still exists.
            guard try await tart.hasOCI(source: image) else { throw error }
            let retry = min(interval, 300)
            nextRefresh[key] = now().addingTimeInterval(retry)
            tart.logger.warning("refresh image \(image) failed: \(error); using cached image, retry on next VM creation after \(retry)s")
        }
    }
}
