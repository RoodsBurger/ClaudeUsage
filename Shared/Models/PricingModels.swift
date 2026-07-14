import Foundation

/// One row of the model price table. Prices are USD per million tokens (MTok).
/// `match` is a list of case-insensitive substrings tested against the raw
/// model id from the JSONL; the first row with any matching substring wins. The
/// fallback row for unknown models carries an empty `match`.
struct PricingEntry: Codable, Sendable, Equatable {
    var match: [String]
    var input: Double
    /// 5-minute cache-write price. The JSONL doesn't reliably split 5m vs 1h
    /// cache creation, so cache_creation tokens are all priced at this rate
    /// (the common case).
    var cacheWrite: Double
    var cacheRead: Double
    var output: Double
    /// Optional human note (e.g. an introductory-pricing caveat). Display-only.
    var note: String?

    func matches(rawModel lowercasedModel: String) -> Bool {
        match.contains { lowercasedModel.contains($0.lowercased()) }
    }
}

/// The full model price table, decoded from the bundled or fetched
/// `pricing.json`. Kept as a plain value type so it can be cached in
/// UserDefaults and priced synchronously off the main thread.
struct PricingTable: Codable, Sendable, Equatable {
    /// Schema version; bumped if the shape changes.
    var version: Int
    /// ISO date the prices were last reviewed (display / provenance only).
    var updated: String?
    /// ISO 4217 code the prices are quoted in. Defaults to USD when absent.
    var currency: String?
    var models: [PricingEntry]

    var currencyCode: String { (currency?.isEmpty == false) ? currency! : "USD" }

    /// Resolves the price row for a raw model id: first `match` hit in order,
    /// else the empty-`match` fallback row, else a hardcoded safe default so a
    /// malformed table never crashes or over/under-charges wildly.
    func price(forRawModel rawModel: String) -> PricingEntry {
        let lowered = rawModel.lowercased()
        if let hit = models.first(where: { !$0.match.isEmpty && $0.matches(rawModel: lowered) }) {
            return hit
        }
        if let fallback = models.first(where: { $0.match.isEmpty }) {
            return fallback
        }
        return PricingEntry(match: [], input: 3, cacheWrite: 3.75, cacheRead: 0.3, output: 15, note: nil)
    }

    /// Last-resort table used only if both the fetched cache and the bundled
    /// copy fail to decode. Mirrors the shipped `pricing.json` defaults.
    static let fallback = PricingTable(
        version: 1,
        updated: nil,
        currency: "USD",
        models: [
            PricingEntry(match: ["fable-5", "mythos-5"], input: 10, cacheWrite: 12.5, cacheRead: 1.0, output: 50, note: nil),
            PricingEntry(match: ["opus-4-8", "opus-4-7", "opus-4-6", "opus-4-5"], input: 5, cacheWrite: 6.25, cacheRead: 0.5, output: 25, note: nil),
            PricingEntry(match: ["sonnet-5"], input: 2, cacheWrite: 2.5, cacheRead: 0.2, output: 10, note: nil),
            PricingEntry(match: ["sonnet-4-6", "sonnet-4-5", "sonnet-4"], input: 3, cacheWrite: 3.75, cacheRead: 0.3, output: 15, note: nil),
            PricingEntry(match: ["haiku-4-5"], input: 1, cacheWrite: 1.25, cacheRead: 0.1, output: 5, note: nil),
            PricingEntry(match: [], input: 3, cacheWrite: 3.75, cacheRead: 0.3, output: 15, note: nil)
        ]
    )
}
