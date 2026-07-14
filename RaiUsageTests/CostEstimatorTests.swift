import Testing
import Foundation

@Suite("CostEstimator")
struct CostEstimatorTests {

    /// The shipped default table (fable / opus / sonnet-5 / sonnet-4-x / haiku
    /// / default). Prices are USD per MTok.
    private let pricing = PricingTable.fallback

    private func bd(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheCreate: Int = 0) -> TokenBreakdown {
        TokenBreakdown(input: input, output: output, cacheRead: cacheRead, cacheCreate: cacheCreate)
    }

    // MARK: - Per-family pricing

    @Test("opus input is priced at $5 / MTok")
    func opusInput() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["claude-opus-4-8": bd(input: 1_000_000)],
            pricing: pricing
        )
        #expect(est.total == 5)
        #expect(est.perModel[.opus48] == 5)
    }

    @Test("opus output is priced at $25 / MTok")
    func opusOutput() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["claude-opus-4-8": bd(output: 1_000_000)],
            pricing: pricing
        )
        #expect(est.total == 25)
    }

    @Test("fable is priced at $10 in / $50 out")
    func fableFamily() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["claude-fable-5": bd(input: 1_000_000, output: 1_000_000)],
            pricing: pricing
        )
        #expect(est.total == 60)
        #expect(est.perModel[.fable] == 60)
    }

    @Test("haiku is priced at $1 in / $5 out")
    func haikuFamily() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["claude-haiku-4-5": bd(input: 1_000_000, output: 1_000_000)],
            pricing: pricing
        )
        #expect(est.total == 6)
        #expect(est.perModel[.haiku] == 6)
    }

    /// sonnet-5 and sonnet-4-6 both fold into `.sonnet` for display but must be
    /// priced at their own distinct rates ($2 vs $3 input).
    @Test("sonnet-5 and sonnet-4-6 price at distinct rates yet fold to one kind")
    func sonnetVersionsPriceDistinctly() {
        let five = CostEstimator.estimate(
            breakdownByRawModel: ["claude-sonnet-5": bd(input: 1_000_000)],
            pricing: pricing
        )
        #expect(five.total == 2)

        let four = CostEstimator.estimate(
            breakdownByRawModel: ["claude-sonnet-4-6": bd(input: 1_000_000)],
            pricing: pricing
        )
        #expect(four.total == 3)

        let both = CostEstimator.estimate(
            breakdownByRawModel: [
                "claude-sonnet-5": bd(input: 1_000_000),
                "claude-sonnet-4-6": bd(input: 1_000_000)
            ],
            pricing: pricing
        )
        #expect(both.perModel[.sonnet] == 5)
        #expect(both.total == 5)
    }

    // MARK: - Fallbacks and edges

    @Test("an unknown model falls through to the default row and maps to .other")
    func unknownModelUsesDefault() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["gpt-5-turbo": bd(input: 1_000_000)],
            pricing: pricing
        )
        #expect(est.total == 3)
        #expect(est.perModel[.other] == 3)
    }

    @Test("zero tokens cost $0 with an empty per-model map")
    func zeroTokensIsFree() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["claude-opus-4-8": .zero],
            pricing: pricing
        )
        #expect(est.total == 0)
        #expect(est.perModel.isEmpty)
    }

    @Test("empty breakdown yields the zero estimate")
    func emptyBreakdown() {
        let est = CostEstimator.estimate(breakdownByRawModel: [:], pricing: pricing)
        #expect(est == .zero)
    }

    @Test("a cache-heavy breakdown prices read and write tokens")
    func cacheHeavyCase() {
        // opus: cacheRead 0.5, cacheWrite 6.25.
        let est = CostEstimator.estimate(
            breakdownByRawModel: ["claude-opus-4-8": bd(cacheRead: 2_000_000, cacheCreate: 1_000_000)],
            pricing: pricing
        )
        // 2M * 0.5 + 1M * 6.25 = 1 + 6.25 = 7.25
        #expect(est.total == 7.25)
        #expect(est.perModel[.opus48] == 7.25)
    }

    @Test("costs sum across multiple models into one total")
    func multiModelTotal() {
        let est = CostEstimator.estimate(
            breakdownByRawModel: [
                "claude-opus-4-8": bd(input: 1_000_000),  // $5
                "claude-haiku-4-5": bd(input: 1_000_000)  // $1
            ],
            pricing: pricing
        )
        #expect(est.total == 6)
        #expect(est.perModel[.opus48] == 5)
        #expect(est.perModel[.haiku] == 1)
    }
}
