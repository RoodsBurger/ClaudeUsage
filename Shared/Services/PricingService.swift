import Foundation

/// Serves the model price table for cost estimates.
///
/// Trust model: the maintained `pricing.json` is fetched from the pinned
/// RoodsBurger/RaiUsage repo over HTTPS (raw.githubusercontent.com), the same
/// pinned-owner-over-TLS chain the in-app updater uses. There is no official
/// Anthropic pricing API, so this maintainer-owned JSON is the "stay current"
/// mechanism. Resolution order for `currentPricing()`:
///   1. last good fetched copy cached in UserDefaults,
///   2. the bundled `pricing.json` shipped in Resources,
///   3. `PricingTable.fallback` (hardcoded) as a final safety net.
final class PricingService: PricingServiceProtocol, @unchecked Sendable {

    /// Pinned raw URL for the maintained table. Kept identical to the copy at
    /// the repo root so this resolves.
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/RoodsBurger/RaiUsage/main/pricing.json")!

    private enum Keys {
        static let cachedJSON = "pricingCachedJSON"
        static let etag = "pricingETag"
        static let lastFetch = "pricingLastFetch"
    }

    /// Auto-refresh throttle. Prices change rarely; a daily poll is plenty and
    /// keeps well clear of any rate limiting.
    private static let refreshInterval: TimeInterval = 24 * 3600

    private let defaults: UserDefaults
    private let bundle: Bundle
    private let session: URLSession

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main, session: URLSession = .shared) {
        self.defaults = defaults
        self.bundle = bundle
        self.session = session
    }

    // MARK: - Read

    func currentPricing() -> PricingTable {
        if let data = defaults.data(forKey: Keys.cachedJSON),
           let table = try? Self.decode(data) {
            return table
        }
        if let data = Self.bundledData(bundle: bundle),
           let table = try? Self.decode(data) {
            return table
        }
        return .fallback
    }

    // MARK: - Refresh

    func refresh(force: Bool) async {
        if !force, let last = defaults.object(forKey: Keys.lastFetch) as? Double,
           Date().timeIntervalSince1970 - last < Self.refreshInterval {
            return
        }

        var request = URLRequest(url: Self.remoteURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag = defaults.string(forKey: Keys.etag) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return
        }

        // 304 Not Modified: the cached copy is still current; just reset the
        // throttle so we don't hammer the endpoint.
        if http.statusCode == 304 {
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastFetch)
            return
        }
        guard http.statusCode == 200, (try? Self.decode(data)) != nil else {
            return
        }

        defaults.set(data, forKey: Keys.cachedJSON)
        if let etag = http.value(forHTTPHeaderField: "Etag") {
            defaults.set(etag, forKey: Keys.etag)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastFetch)
    }

    // MARK: - Pure helpers

    /// Decodes a table and rejects an empty/garbage one so a bad fetch can't
    /// blank out prices. Separated from the network call so tests drive it with
    /// fixture data.
    static func decode(_ data: Data) throws -> PricingTable {
        let table = try JSONDecoder().decode(PricingTable.self, from: data)
        guard !table.models.isEmpty else { throw PricingServiceError.emptyTable }
        return table
    }

    static func bundledData(bundle: Bundle) -> Data? {
        guard let url = bundle.url(forResource: "pricing", withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }
}

enum PricingServiceError: Error {
    case emptyTable
}
