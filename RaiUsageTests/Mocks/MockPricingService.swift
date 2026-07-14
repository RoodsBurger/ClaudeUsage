import Foundation

final class MockPricingService: PricingServiceProtocol, @unchecked Sendable {
    var stubbedTable: PricingTable
    private(set) var refreshCallCount = 0
    private(set) var lastRefreshForced = false

    init(stubbedTable: PricingTable = .fallback) {
        self.stubbedTable = stubbedTable
    }

    func currentPricing() -> PricingTable { stubbedTable }

    func refresh(force: Bool) async {
        refreshCallCount += 1
        lastRefreshForced = force
    }
}
