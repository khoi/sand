import Foundation
import XCTest
@testable import sand

final class MockAuth: GitHubAuthenticating, @unchecked Sendable {
    func token(now: Date) throws -> String {
        return "jwt"
    }
}

final class MockSession: URLSessionProtocol, @unchecked Sendable {
    var responses: [String: (Data, Int)] = [:]
    var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url?.path ?? ""
        guard let response = responses[path] else {
            throw NSError(domain: "missing", code: 1)
        }
        let url = request.url ?? URL(string: "https://api.github.com")!
        let http = HTTPURLResponse(url: url, statusCode: response.1, httpVersion: nil, headerFields: nil)!
        return (response.0, http)
    }
}

final class GitHubServiceTests: XCTestCase {
    func testRepoLevelPaths() async throws {
        let session = MockSession()
        session.responses["/repos/org/repo/installation"] = (Data("{\"id\":1}".utf8), 200)
        session.responses["/app/installations/1/access_tokens"] = (Data("{\"token\":\"access\"}".utf8), 200)
        session.responses["/repos/org/repo/actions/runners/registration-token"] = (Data("{\"token\":\"runner\"}".utf8), 200)
        let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: "repo")
        let token = try await service.runnerRegistrationToken()
        XCTAssertEqual(token, "runner")
        XCTAssertEqual(session.requests.map { $0.url?.path ?? "" }, [
            "/repos/org/repo/installation",
            "/app/installations/1/access_tokens",
            "/repos/org/repo/actions/runners/registration-token"
        ])
    }

    func testDeleteRunnerLooksUpByNameThenDeletes() async throws {
        let session = MockSession()
        session.responses["/orgs/org/installation"] = (Data("{\"id\":1}".utf8), 200)
        session.responses["/app/installations/1/access_tokens"] = (Data("{\"token\":\"access\"}".utf8), 200)
        session.responses["/orgs/org/actions/runners"] = (Data("{\"total_count\":1,\"runners\":[{\"id\":7,\"name\":\"runner 1+x\"}]}".utf8), 200)
        session.responses["/orgs/org/actions/runners/7"] = (Data(), 204)
        let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: nil)
        let deleted = try await service.deleteRunner(named: "runner 1+x")
        XCTAssertTrue(deleted)
        XCTAssertEqual(session.requests[2].url?.query, "name=runner%201%2Bx")
        XCTAssertEqual(session.requests[3].httpMethod, "DELETE")
        XCTAssertEqual(session.requests[3].url?.path, "/orgs/org/actions/runners/7")
    }

    func testDeleteRunnerSkipsMissingRunner() async throws {
        let session = MockSession()
        session.responses["/repos/org/repo/installation"] = (Data("{\"id\":1}".utf8), 200)
        session.responses["/app/installations/1/access_tokens"] = (Data("{\"token\":\"access\"}".utf8), 200)
        session.responses["/repos/org/repo/actions/runners"] = (Data("{\"total_count\":0,\"runners\":[]}".utf8), 200)
        let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: "repo")
        let deleted = try await service.deleteRunner(named: "runner-1-abcde")
        XCTAssertFalse(deleted)
        XCTAssertEqual(session.requests.count, 3)
    }
}
