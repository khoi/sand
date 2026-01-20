import Foundation
import XCTest
@testable import sand

final class GitHubAuthTests: XCTestCase {
    func testJwtClaims() throws {
        let key = """
        -----BEGIN PRIVATE KEY-----
        MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCuIBryNQJtQjys
        Q2xOt7alMuh88qUl/wmR1xsV+wlS1uKFrMum04TdEr0Xkzlivropn2zRu0SkR7Ke
        j+dYDiYTmKt+rO0yShW4wg86K/mhdXTX5gd9KRNJpyU0DbAJK0FCAU4vwtL0ixgt
        53UdQawm1VxkACNejnKjTINXd9+6RgJAyu8wCzvd5K4ohhTEPh1+v+/Jz4W9rjRR
        HJNvOeP3ub7hGMCSdvyyumDvVwn7Me0UXfps6MzvUS1VqgoOVegzHbdc/HIl3Q9t
        x/WjJfjWJROzyLs7qSRciY+/+lAQ6s8Dl/2tPZdrUmElYNK0eG6i9w9uZzeaefQb
        sDkxF5NFAgMBAAECggEAF7qSUX191ivXntYVVWjdwAd+/UAH13S49iHtNAKg06Qq
        /HJ+0j4y9fmOwT6z7Ev3jKKILtCpWwXWRptvuGU9NSByBnJEZL0J1sLDVncVrrYV
        9TIIxTqqwTfA7yYKXkWBwB/zarjPDLpD0kWfhRwk/KnIzGvkZgddgfl0UKAqYfTc
        taz9jPfdI8HIKkKEdXGA8CiKtPATKvz7sk6yLhf5/1niPnT/3O94f5ObshByvWLs
        RLemrsVesgLFbQIAp2BDULqL3bxLlkrADNI9MkksqHJMftEeqNq5tHAh0zabtyyO
        YDgG7CbrDnOTnDJsOza9ok1yAv0XCG2XuQJVdTpDBQKBgQDj14yianr0vyRiBrUE
        tuuLNtKhB7iu5KGJwzeJmQHZmAouWXOpNsV3hAH9hpl2Z2LzoxiJhop8Hz69x2xI
        01ReMOWFrKn8+Gl3VMmWvaDO1iGo3Ea/Tj0Rqg1axbMYy4tafVxcPPaEEl3eR7YZ
        xbNUDZakVnSLu8GQVEHTR4iRgwKBgQDDpRL7VoGvRJ5rJUP09yqLlU57sJw9Sro1
        VohpELfSq3o0E/pUVCyBgxrI48q11fmi+Q5O67LN6847Ke7SwxslI7tfg8X3GHWt
        Q5vonO6JCGJw26V8Qf/K1NRe2J0ukDUS3zHwJTXtrBArnljCWE/1JZV+1KuOC1x1
        l0YVNN4VlwKBgQCTCWoS7tDG3gvmzxlHH51GzGyFy2veQmIVe8x9mibdfAcl/khs
        LZKmHKUELjcfeH0damXNauw4Shm9c9Nn9CoAV2HoMJPLU60Me8VU6K+8i+hRB0cI
        8r7qhWn06J06JTGbhkdyp00X0pqNdo4Id9PRLKvJBppUCylRsW6BoSp7bQKBgHWV
        VJ8yEqcf+oYy03D6y9swVQcJ0h0UOG2uIDXlElXPMZbzGtRr8oO0I/jwzvgSLgLA
        5NSR29jfDAeK4DpTgJEFtKtnKyeiz7bel2lqSAKbw25I1GCl2fIxj6GhVnaRvRQm
        iIDoHE1HyEAu3vGO2h9gA0VC1Ah+04bo7/n22DLpAoGBAMtZLaG8gUjbQAVSpotY
        PfImxpR0zJ0Q3pj9oSgNbzcYftY47R+IeoBTfQowsAz1B2O9Mw6dPRaSV9nFBzGi
        xVpF50nS2JnSAJjQMT9bZU1VbETn3dsbCGcbi2eqWRRobetT7V7Dg9tWaKK9eHCe
        +x2NVuqWk4s8inTmI068rDdy
        -----END PRIVATE KEY-----
        """
        let keyURL = try writeTempFile(contents: key, suffix: ".pem")
        let auth = try GitHubAuth(appId: 123, privateKeyPath: keyURL.path)
        let now = Date(timeIntervalSince1970: 1000)
        let token = try auth.token(now: now)
        let claims = try decodeJWTClaims(token)
        XCTAssertEqual(claims["iss"] as? String, "123")
        XCTAssertEqual((claims["iat"] as? NSNumber)?.intValue, 990)
        XCTAssertEqual((claims["exp"] as? NSNumber)?.intValue, 1060)
    }
}
