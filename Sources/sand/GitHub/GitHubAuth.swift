import Foundation
import SwiftJWT

struct GitHubClaims: Claims {
    let iss: String
    let iat: Date
    let exp: Date

    func encode() throws -> String {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int(date.timeIntervalSince1970))
        }
        let data = try jsonEncoder.encode(self)
        return JWTEncoder.base64urlEncodedString(data: data)
    }
}

protocol GitHubAuthenticating {
    func token(now: Date) throws -> String
}

struct GitHubAuth: GitHubAuthenticating {
    let appId: Int
    let privateKey: Data

    init(appId: Int, privateKeyPath: String) throws {
        self.appId = appId
        self.privateKey = try Data(contentsOf: URL(fileURLWithPath: privateKeyPath))
    }

    func token(now: Date = Date()) throws -> String {
        let issuedAt = now.addingTimeInterval(-10)
        let expiresAt = now.addingTimeInterval(60)
        let claims = GitHubClaims(iss: String(appId), iat: issuedAt, exp: expiresAt)
        var jwt = JWT(claims: claims)
        let signer = JWTSigner.rs256(privateKey: privateKey)
        return try jwt.sign(using: signer)
    }
}
