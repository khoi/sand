import XCTest
@testable import sand

final class RestartBackoffTests: XCTestCase {
    func testBackoffIncreasesForSameReason() async {
        let policy = RestartBackoffPolicy(baseDelay: 1, maxDelay: 8, multiplier: 2)
        let backoff = RestartBackoff(policy: policy)
        let first = await backoff.schedule(reason: .sshNotReady)
        let second = await backoff.schedule(reason: .sshNotReady)
        let third = await backoff.schedule(reason: .sshNotReady)
        let fourth = await backoff.schedule(reason: .sshNotReady)
        let fifth = await backoff.schedule(reason: .sshNotReady)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(third, 4)
        XCTAssertEqual(fourth, 8)
        XCTAssertEqual(fifth, 8)
    }

    func testBackoffResetsOnReasonChange() async {
        let policy = RestartBackoffPolicy(baseDelay: 1, maxDelay: 60, multiplier: 2)
        let backoff = RestartBackoff(policy: policy)
        let first = await backoff.schedule(reason: .sshNotReady)
        let second = await backoff.schedule(reason: .sshNotReady)
        let third = await backoff.schedule(reason: .stageFailed("preRun"))
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        XCTAssertEqual(third, 1)
    }

    func testTakePendingClearsDelay() async {
        let policy = RestartBackoffPolicy(baseDelay: 1, maxDelay: 60, multiplier: 2)
        let backoff = RestartBackoff(policy: policy)
        _ = await backoff.schedule(reason: .sshNotReady)
        let pending = await backoff.takePending()
        let next = await backoff.takePending()
        XCTAssertEqual(pending.0, 1)
        XCTAssertEqual(next.0, 0)
    }
}
