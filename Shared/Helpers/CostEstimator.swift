import Foundation

/// Pure cost calculator. Turns a per-raw-model token breakdown into an
/// estimated USD cost using a `PricingTable`. Every raw model id is priced
/// individually (so `sonnet-5` and `sonnet-4-6` charge their own rates), then
/// costs are aggregated up to `ModelKind` for display plus a grand total.
///
/// The number is an ESTIMATE from published list prices and can diverge from a
/// negotiated enterprise bill; the UI labels it as such.
enum CostEstimator {

    /// Per-model and total estimated cost, in the pricing table's currency
    /// (USD by default), expressed in major units (dollars, not cents).
    struct Estimate: Sendable, Equatable {
        let perModel: [ModelKind: Double]
        let total: Double

        static let zero = Estimate(perModel: [:], total: 0)
    }

    /// Cost of a single model's token split at the given price row.
    /// input*in + output*out + cacheRead*read + cacheCreate*write, per MTok.
    static func cost(of breakdown: TokenBreakdown, price: PricingEntry) -> Double {
        (Double(breakdown.input) * price.input
            + Double(breakdown.output) * price.output
            + Double(breakdown.cacheRead) * price.cacheRead
            + Double(breakdown.cacheCreate) * price.cacheWrite) / 1_000_000
    }

    /// Estimates cost for a per-raw-model breakdown. Unknown model ids fall
    /// through to the pricing table's default row. Empty input yields
    /// `.zero` (total 0).
    static func estimate(breakdownByRawModel: [String: TokenBreakdown], pricing: PricingTable) -> Estimate {
        var perModel: [ModelKind: Double] = [:]
        var total = 0.0
        for (rawModel, breakdown) in breakdownByRawModel {
            let price = pricing.price(forRawModel: rawModel)
            let c = cost(of: breakdown, price: price)
            guard c != 0 else { continue }
            perModel[ModelKind(rawModel: rawModel), default: 0] += c
            total += c
        }
        return Estimate(perModel: perModel, total: total)
    }
}
