import Foundation
import Testing
@testable import sand

final class MockAuth: GitHubAuthenticating {
    func token(now: Date) throws -> String {
        return "jwt"
    }
}

final class MockSession: URLSessionProtocol {
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

@Test
func repoLevelPaths() async throws {
    let session = MockSession()
    session.responses["/repos/org/repo/installation"] = (Data("{\"id\":1}".utf8), 200)
    session.responses["/app/installations/1/access_tokens"] = (Data("{\"token\":\"access\"}".utf8), 200)
    session.responses["/repos/org/repo/actions/runners/registration-token"] = (Data("{\"token\":\"runner\"}".utf8), 200)
    let service = GitHubService(auth: MockAuth(), session: session, organization: "org", repository: "repo")
    let token = try await service.runnerRegistrationToken()
    #expect(token == "runner")
    #expect(session.requests.map { $0.url?.path ?? "" } == [
        "/repos/org/repo/installation",
        "/app/installations/1/access_tokens",
        "/repos/org/repo/actions/runners/registration-token"
    ])
}
