import Testing
import Foundation

@Suite("PricingService")
struct PricingServiceTests {

    /// Mirrors the shipped `pricing.json` schema, extra field included to prove
    /// decoding tolerates unknown keys is not required — but the note field is.
    private static let json = """
    {
      "version": 1,
      "updated": "2026-07-01",
      "currency": "USD",
      "models": [
        { "match": ["fable-5", "mythos-5"], "input": 10, "cacheWrite": 12.5, "cacheRead": 1.0, "output": 50 },
        { "match": ["opus-4-8", "opus-4-7", "opus-4-6", "opus-4-5"], "input": 5, "cacheWrite": 6.25, "cacheRead": 0.5, "output": 25 },
        { "match": ["sonnet-5"], "input": 2, "cacheWrite": 2.5, "cacheRead": 0.2, "output": 10, "note": "Intro." },
        { "match": ["sonnet-4-6", "sonnet-4-5", "sonnet-4"], "input": 3, "cacheWrite": 3.75, "cacheRead": 0.3, "output": 15 },
        { "match": ["haiku-4-5"], "input": 1, "cacheWrite": 1.25, "cacheRead": 0.1, "output": 5 },
        { "match": [], "input": 3, "cacheWrite": 3.75, "cacheRead": 0.3, "output": 15 }
      ]
    }
    """

    private var fixture: Data { Data(Self.json.utf8) }

    // MARK: - Decode

    @Test("valid JSON decodes into a table")
    func decodesValidTable() throws {
        let table = try PricingService.decode(fixture)
        #expect(table.version == 1)
        #expect(table.currencyCode == "USD")
        #expect(table.models.count == 6)
        #expect(table.updated == "2026-07-01")
    }

    @Test("an empty model list is rejected fail-closed")
    func emptyTableThrows() {
        let json = #"{ "version": 1, "models": [] }"#
        #expect(throws: PricingServiceError.emptyTable) {
            try PricingService.decode(Data(json.utf8))
        }
    }

    @Test("malformed JSON throws")
    func malformedThrows() {
        #expect(throws: (any Error).self) {
            try PricingService.decode(Data("not json".utf8))
        }
    }

    @Test("currency falls back to USD when absent")
    func currencyDefault() throws {
        let json = #"{ "version": 1, "models": [ { "match": [], "input": 3, "cacheWrite": 3, "cacheRead": 0.3, "output": 15 } ] }"#
        let table = try PricingService.decode(Data(json.utf8))
        #expect(table.currencyCode == "USD")
    }

    // MARK: - Matching

    @Test("raw model ids resolve to their price row by first substring hit")
    func matchingByRawModel() throws {
        let table = try PricingService.decode(fixture)
        #expect(table.price(forRawModel: "claude-opus-4-8").input == 5)
        #expect(table.price(forRawModel: "claude-opus-4-6[1m]").input == 5)
        #expect(table.price(forRawModel: "claude-fable-5").input == 10)
        #expect(table.price(forRawModel: "claude-haiku-4-5").input == 1)
    }

    @Test("sonnet-5 and sonnet-4-6 resolve to their own distinct rows")
    func sonnetVersionMatching() throws {
        let table = try PricingService.decode(fixture)
        #expect(table.price(forRawModel: "claude-sonnet-5").input == 2)
        #expect(table.price(forRawModel: "claude-sonnet-4-6").input == 3)
    }

    @Test("an unknown model resolves to the empty-match default row")
    func unknownMatchesDefault() throws {
        let table = try PricingService.decode(fixture)
        let price = table.price(forRawModel: "some-future-model")
        #expect(price.match.isEmpty)
        #expect(price.input == 3)
        #expect(price.output == 15)
    }

    @Test("matching is case-insensitive")
    func caseInsensitiveMatch() throws {
        let table = try PricingService.decode(fixture)
        #expect(table.price(forRawModel: "CLAUDE-OPUS-4-8").input == 5)
    }

    // MARK: - Bundled copy + fallback resolution

    /// The `pricing.json` shipped in Resources must decode and price every
    /// family. It is copied into the test bundle too, so we read it from there.
    @Test("the bundled pricing.json is valid and prices every family")
    func bundledResourceIsValid() throws {
        let bundle = Bundle(for: MockPricingService.self)
        let data = try #require(PricingService.bundledData(bundle: bundle))
        let table = try PricingService.decode(data)
        #expect(table.price(forRawModel: "claude-fable-5").input == 10)
        #expect(table.price(forRawModel: "claude-opus-4-8").input == 5)
        #expect(table.price(forRawModel: "claude-sonnet-5").input == 2)
        #expect(table.price(forRawModel: "claude-sonnet-4-6").input == 3)
        #expect(table.price(forRawModel: "claude-haiku-4-5").input == 1)
        #expect(table.price(forRawModel: "unknown").input == 3)
    }

    @Test("currentPricing falls back to the bundled copy when no cache exists")
    func currentPricingFallsBackToBundle() {
        let suiteName = "PricingServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = PricingService(defaults: defaults, bundle: Bundle(for: MockPricingService.self))
        let table = service.currentPricing()
        #expect(!table.models.isEmpty)
        #expect(table.price(forRawModel: "claude-opus-4-8").input == 5)
    }

    @Test("currentPricing prefers a cached fetched copy over the bundle")
    func currentPricingPrefersCache() {
        let suiteName = "PricingServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // Cache a table whose opus price differs from the bundled one.
        let cached = #"{ "version": 9, "models": [ { "match": ["opus"], "input": 99, "cacheWrite": 1, "cacheRead": 1, "output": 1 } ] }"#
        defaults.set(Data(cached.utf8), forKey: "pricingCachedJSON")
        let service = PricingService(defaults: defaults, bundle: Bundle(for: MockPricingService.self))
        #expect(service.currentPricing().version == 9)
        #expect(service.currentPricing().price(forRawModel: "claude-opus-4-8").input == 99)
    }

    @Test("the remote URL pins the maintainer repo raw content over HTTPS")
    func remoteURLIsPinned() {
        #expect(PricingService.remoteURL.absoluteString
            == "https://raw.githubusercontent.com/RoodsBurger/RaiUsage/main/pricing.json")
    }
}
