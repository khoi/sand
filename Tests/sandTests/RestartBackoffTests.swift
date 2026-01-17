import Testing
@testable import sand

@Test
func backoffIncreasesForSameReason() {
    let policy = RestartBackoffPolicy(baseDelay: 1, maxDelay: 8, multiplier: 2)
    let backoff = RestartBackoff(policy: policy)
    #expect(backoff.schedule(reason: .sshNotReady) == 1)
    #expect(backoff.schedule(reason: .sshNotReady) == 2)
    #expect(backoff.schedule(reason: .sshNotReady) == 4)
    #expect(backoff.schedule(reason: .sshNotReady) == 8)
    #expect(backoff.schedule(reason: .sshNotReady) == 8)
}

@Test
func backoffResetsOnReasonChange() {
    let policy = RestartBackoffPolicy(baseDelay: 1, maxDelay: 60, multiplier: 2)
    let backoff = RestartBackoff(policy: policy)
    #expect(backoff.schedule(reason: .sshNotReady) == 1)
    #expect(backoff.schedule(reason: .sshNotReady) == 2)
    #expect(backoff.schedule(reason: .stageFailed("preRun")) == 1)
}

@Test
func takePendingClearsDelay() {
    let policy = RestartBackoffPolicy(baseDelay: 1, maxDelay: 60, multiplier: 2)
    let backoff = RestartBackoff(policy: policy)
    _ = backoff.schedule(reason: .sshNotReady)
    let pending = backoff.takePending()
    #expect(pending.0 == 1)
    let next = backoff.takePending()
    #expect(next.0 == 0)
}
