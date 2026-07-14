import Testing
import Foundation

@Suite("BorrowedCredential")
struct BorrowedCredentialTests {

    @Test("isExpired is false when expiresAt is nil")
    func isExpiredNilExpiry() {
        let credential = BorrowedCredential(accessToken: "a", refreshToken: nil, expiresAt: nil)
        #expect(credential.isExpired() == false)
    }

    @Test("isExpired is false for a future expiresAt")
    func isExpiredFuture() {
        let now = Date()
        let credential = BorrowedCredential(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(60))
        #expect(credential.isExpired(now: now) == false)
    }

    @Test("isExpired is true for a past expiresAt")
    func isExpiredPast() {
        let now = Date()
        let credential = BorrowedCredential(accessToken: "a", refreshToken: nil, expiresAt: now.addingTimeInterval(-60))
        #expect(credential.isExpired(now: now) == true)
    }

    @Test("isExpired is true exactly at expiresAt")
    func isExpiredExactlyAtBoundary() {
        let now = Date()
        let credential = BorrowedCredential(accessToken: "a", refreshToken: nil, expiresAt: now)
        #expect(credential.isExpired(now: now) == true)
    }

    @Test("needsRefresh is false when expiresAt is nil")
    func needsRefreshNilExpiry() {
        let credential = BorrowedCredential(accessToken: "a", refreshToken: "r", expiresAt: nil)
        #expect(credential.needsRefresh() == false)
    }

    @Test("needsRefresh is false outside the margin")
    func needsRefreshOutsideMargin() {
        let now = Date()
        let credential = BorrowedCredential(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(600))
        #expect(credential.needsRefresh(now: now) == false)
    }

    @Test("needsRefresh is true within the default 300s margin")
    func needsRefreshWithinMargin() {
        let now = Date()
        let credential = BorrowedCredential(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(100))
        #expect(credential.needsRefresh(now: now) == true)
    }

    @Test("needsRefresh is true when already past expiry")
    func needsRefreshPastExpiry() {
        let now = Date()
        let credential = BorrowedCredential(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(-100))
        #expect(credential.needsRefresh(now: now) == true)
    }

    @Test("BorrowedCredential is Equatable")
    func equatable() {
        let expiresAt = Date()
        let a = BorrowedCredential(accessToken: "tok", refreshToken: "ref", expiresAt: expiresAt)
        let b = BorrowedCredential(accessToken: "tok", refreshToken: "ref", expiresAt: expiresAt)
        let c = BorrowedCredential(accessToken: "other", refreshToken: "ref", expiresAt: expiresAt)
        #expect(a == b)
        #expect(a != c)
    }
}
