import Foundation

/// Supplies the model price table used to estimate cost. The current table is
/// always available synchronously (cached fetch, else bundled copy, else a
/// hardcoded fallback) so the UI never blocks; `refresh()` updates the cache in
/// the background from the maintained remote JSON.
protocol PricingServiceProtocol: Sendable {
    /// Best table available right now, without any I/O beyond a cheap decode.
    /// Never throws: falls back through last-good-fetch -> bundled -> hardcoded.
    func currentPricing() -> PricingTable

    /// Fetches the maintained remote `pricing.json` and updates the cache when
    /// it changed. Throttled internally (24h) unless `force` is set. Never
    /// throws to the caller: a failed fetch simply keeps the last good table.
    func refresh(force: Bool) async
}

extension PricingServiceProtocol {
    func refresh() async { await refresh(force: false) }
}
