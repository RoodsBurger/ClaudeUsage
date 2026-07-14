import Testing
import Foundation

@Suite("UpdateChecker")
struct UpdateCheckerTests {

    /// Realistic slice of the GitHub "get latest release" payload, extra
    /// fields included to prove decoding ignores them.
    private static let releaseJSON = """
    {
      "tag_name": "v9.9.9",
      "name": "RaiUsage v9.9.9",
      "html_url": "https://github.com/RoodsBurger/RaiUsage/releases/tag/v9.9.9",
      "prerelease": false,
      "assets": [
        {
          "name": "checksums.txt",
          "size": 128,
          "browser_download_url": "https://github.com/RoodsBurger/RaiUsage/releases/download/v9.9.9/checksums.txt"
        },
        {
          "name": "RaiUsage-v9.9.9.dmg",
          "size": 4200000,
          "browser_download_url": "https://github.com/RoodsBurger/RaiUsage/releases/download/v9.9.9/RaiUsage-v9.9.9.dmg"
        }
      ]
    }
    """

    private var fixture: Data { Data(Self.releaseJSON.utf8) }

    @Test("a newer release decodes into UpdateInfo")
    func decodesNewerRelease() throws {
        let info = try UpdateChecker.updateInfo(from: fixture, currentVersion: "5.8.0")
        #expect(info != nil)
        #expect(info?.version == "9.9.9")
        #expect(info?.releaseURL.absoluteString == "https://github.com/RoodsBurger/RaiUsage/releases/tag/v9.9.9")
        #expect(info?.dmgURL.absoluteString == "https://github.com/RoodsBurger/RaiUsage/releases/download/v9.9.9/RaiUsage-v9.9.9.dmg")
    }

    @Test("the .dmg asset is picked even when it is not first")
    func picksDMGAmongAssets() throws {
        let info = try UpdateChecker.updateInfo(from: fixture, currentVersion: "1.0.0")
        #expect(info?.dmgURL.lastPathComponent == "RaiUsage-v9.9.9.dmg")
    }

    @Test("an equal version resolves to nil (up to date)")
    func equalVersionIsUpToDate() throws {
        let info = try UpdateChecker.updateInfo(from: fixture, currentVersion: "9.9.9")
        #expect(info == nil)
    }

    @Test("an older release resolves to nil, never a downgrade")
    func olderReleaseIsUpToDate() throws {
        let info = try UpdateChecker.updateInfo(from: fixture, currentVersion: "10.0.0")
        #expect(info == nil)
    }

    @Test("a newer release without a DMG asset throws fail-closed")
    func missingDMGThrows() {
        let json = """
        {
          "tag_name": "v9.9.9",
          "html_url": "https://github.com/RoodsBurger/RaiUsage/releases/tag/v9.9.9",
          "assets": [
            { "name": "checksums.txt", "browser_download_url": "https://example.com/checksums.txt" }
          ]
        }
        """
        #expect(throws: UpdateCheckerError.noDMGAsset) {
            try UpdateChecker.updateInfo(from: Data(json.utf8), currentVersion: "5.8.0")
        }
    }

    @Test("malformed JSON throws badResponse")
    func malformedJSONThrows() {
        #expect(throws: UpdateCheckerError.badResponse) {
            try UpdateChecker.updateInfo(from: Data("not json".utf8), currentVersion: "5.8.0")
        }
    }

    @Test("the latest-release endpoint pins the owner repo over HTTPS")
    func endpointIsPinned() {
        #expect(UpdateChecker.latestReleaseURL.absoluteString
            == "https://api.github.com/repos/RoodsBurger/RaiUsage/releases/latest")
    }
}
