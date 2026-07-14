import Testing
import Foundation

@Suite("PKCE")
struct PKCETests {
    @Test("generateVerifier produces 43-character base64url string")
    func generateVerifierLength() {
        let verifier = PKCE.generateVerifier()
        #expect(verifier.count == 43)
    }

    @Test("generateVerifier uses only base64url characters")
    func generateVerifierCharset() {
        let verifier = PKCE.generateVerifier()
        let base64urlPattern = "^[A-Za-z0-9_-]+$"
        let regex = try! NSRegularExpression(pattern: base64urlPattern)
        let range = NSRange(verifier.startIndex..., in: verifier)
        let match = regex.firstMatch(in: verifier, range: range)
        #expect(match != nil)
    }

    @Test("generateVerifier produces different values on repeated calls")
    func generateVerifierRandomness() {
        let v1 = PKCE.generateVerifier()
        let v2 = PKCE.generateVerifier()
        #expect(v1 != v2)
    }

    @Test("RFC 7636 test vector: known verifier produces correct challenge")
    func rfc7636TestVector() {
        let testVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let expectedChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        let challenge = PKCE.challenge(for: testVerifier)
        #expect(challenge == expectedChallenge)
    }

    @Test("challenge is base64url encoded with no padding")
    func challengeFormatting() {
        let verifier = PKCE.generateVerifier()
        let challenge = PKCE.challenge(for: verifier)
        // Should contain only base64url chars and no padding (=)
        let base64urlPattern = "^[A-Za-z0-9_-]+$"
        let regex = try! NSRegularExpression(pattern: base64urlPattern)
        let range = NSRange(challenge.startIndex..., in: challenge)
        let match = regex.firstMatch(in: challenge, range: range)
        #expect(match != nil)
        #expect(!challenge.contains("="))
    }
}
