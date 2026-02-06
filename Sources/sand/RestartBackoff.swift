import Foundation

enum RestartReason: Equatable, CustomStringConvertible {
    case healthCheckFailed(String)
    case ipNotReady
    case sshNotReady
    case stageFailed(String)
    case provisionerExited

    var description: String {
        switch self {
        case let .healthCheckFailed(message):
            return "healthcheck failed: \(message)"
        case .ipNotReady:
            return "ip not ready"
        case .sshNotReady:
            return "ssh not ready"
        case let .stageFailed(stage):
            return "\(stage) failed"
        case .provisionerExited:
            return "provisioner exited"
        }
    }
}

struct RestartBackoffPolicy {
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let multiplier: Double

    static let standard = RestartBackoffPolicy(baseDelay: 1, maxDelay: 60, multiplier: 2)
}

struct RestartBackoffState: CustomStringConvertible {
    let attempt: Int
    let pendingDelay: TimeInterval
    let pendingReason: RestartReason?
    let lastReason: RestartReason?

    var description: String {
        let pendingReasonLabel = pendingReason.map(String.init(describing:)) ?? "none"
        let lastReasonLabel = lastReason.map(String.init(describing:)) ?? "none"
        return "attempt=\(attempt) pendingDelay=\(pendingDelay)s pendingReason=\(pendingReasonLabel) lastReason=\(lastReasonLabel)"
    }
}

actor RestartBackoff {
    private let policy: RestartBackoffPolicy
    private var attempt: Int = 0
    private var pendingDelay: TimeInterval = 0
    private var pendingReason: RestartReason?
    private var lastReason: RestartReason?

    init(policy: RestartBackoffPolicy = .standard) {
        self.policy = policy
    }

    @discardableResult
    func schedule(reason: RestartReason) -> TimeInterval {
        if let lastReason, lastReason == reason {
            attempt += 1
        } else {
            attempt = 1
            lastReason = reason
        }
        let rawDelay = policy.baseDelay * pow(policy.multiplier, Double(max(0, attempt - 1)))
        let delay = min(rawDelay, policy.maxDelay)
        pendingDelay = delay
        pendingReason = reason
        return delay
    }

    func takePending() -> (TimeInterval, RestartReason?) {
        let delay = pendingDelay
        let reason = pendingReason
        pendingDelay = 0
        pendingReason = nil
        return (delay, reason)
    }

    func reset() {
        attempt = 0
        pendingDelay = 0
        pendingReason = nil
        lastReason = nil
    }

    func snapshot() -> RestartBackoffState {
        let state = RestartBackoffState(
            attempt: attempt,
            pendingDelay: pendingDelay,
            pendingReason: pendingReason,
            lastReason: lastReason
        )
        return state
    }
}
