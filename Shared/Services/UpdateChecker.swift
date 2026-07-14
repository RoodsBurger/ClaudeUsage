import Foundation

/// GitHub Releases update check.
///
/// Trust model: the check and the download both target the pinned
/// RoodsBurger/RaiUsage repository over HTTPS (api.github.com). Releases
/// are ad-hoc-signed DMGs with no notarization and no signature feed, so TLS
/// plus the hardcoded owner/repo is the whole chain of trust - acceptable
/// for a personal fork, not for broad distribution.
final class UpdateChecker: UpdateCheckerProtocol, @unchecked Sendable {
    /// GitHub REST "get latest release" for the pinned repo. Unauthenticated;
    /// `UpdateStore`'s 24h auto-check throttle keeps usage far below the
    /// anonymous rate limit.
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/RoodsBurger/RaiUsage/releases/latest")!

    private let currentVersion: String

    init(currentVersion: String? = nil) {
        self.currentVersion = currentVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0"
    }

    func checkLatest() async throws -> UpdateInfo? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateCheckerError.badResponse
        }
        return try Self.updateInfo(from: data, currentVersion: currentVersion)
    }

    /// Pure decode + version-compare step, separated from the network call so
    /// tests can drive it with fixture JSON.
    static func updateInfo(from data: Data, currentVersion: String) throws -> UpdateInfo? {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw UpdateCheckerError.badResponse
        }
        guard UpdateVersion.isNewer(release.tagName, than: currentVersion) else { return nil }
        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            throw UpdateCheckerError.noDMGAsset
        }
        return UpdateInfo(
            version: UpdateVersion.normalized(release.tagName),
            releaseURL: release.htmlURL,
            dmgURL: dmg.browserDownloadURL
        )
    }
}
