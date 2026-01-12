import Foundation

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

enum GitHubServiceError: Error {
    case invalidResponse
    case httpError(status: Int, body: String)
}

struct GitHubService {
    struct InstallationResponse: Decodable {
        let id: Int
    }

    struct AccessTokenResponse: Decodable {
        let token: String
    }

    struct RunnerTokenResponse: Decodable {
        let token: String
    }


    let auth: GitHubAuthenticating
    let session: URLSessionProtocol
    let organization: String
    let repository: String?
    let baseURL = URL(string: "https://api.github.com")!

    func runnerRegistrationToken() async throws -> String {
        let installationId = try await installationID()
        let accessToken = try await installationAccessToken(installationId: installationId)
        let tokenResponse: RunnerTokenResponse = try await request(path: registrationTokenPath(), method: "POST", token: accessToken)
        return tokenResponse.token
    }


    private func installationID() async throws -> Int {
        let token = try auth.token(now: Date())
        let response: InstallationResponse = try await request(path: installationPath(), method: "GET", token: token)
        return response.id
    }

    private func installationAccessToken(installationId: Int) async throws -> String {
        let token = try auth.token(now: Date())
        let response: AccessTokenResponse = try await request(path: "/app/installations/\(installationId)/access_tokens", method: "POST", token: token)
        return response.token
    }

    private func request<T: Decodable>(path: String, method: String, token: String) async throws -> T {
        let url = URL(string: path, relativeTo: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("sand", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubServiceError.invalidResponse
        }
        if !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GitHubServiceError.httpError(status: httpResponse.statusCode, body: body)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func installationPath() -> String {
        if let repository {
            return "/repos/\(organization)/\(repository)/installation"
        }
        return "/orgs/\(organization)/installation"
    }

    private func registrationTokenPath() -> String {
        if let repository {
            return "/repos/\(organization)/\(repository)/actions/runners/registration-token"
        }
        return "/orgs/\(organization)/actions/runners/registration-token"
    }

}
