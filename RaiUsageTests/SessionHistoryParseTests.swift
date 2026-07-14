import Testing
import Foundation

/// Covers the pure per-line JSONL aggregation, focusing on the per raw-model
/// `TokenBreakdown` split that backs the cost estimate. The wider file/cache
/// machinery around it is exercised indirectly by the History store tests.
@Suite("SessionHistoryService.parse")
struct SessionHistoryParseTests {

    /// Builds one JSONL line for an assistant turn carrying token usage.
    private func line(
        ts: String,
        session: String = "s1",
        cwd: String = "/tmp/proj",
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int = 0,
        cacheCreate: Int = 0
    ) -> String {
        """
        {"timestamp":"\(ts)","sessionId":"\(session)","cwd":"\(cwd)","message":{"model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),"cache_read_input_tokens":\(cacheRead),"cache_creation_input_tokens":\(cacheCreate)}}}
        """
    }

    private func onlyBucket(_ content: String) -> HistoryBucket {
        let parsed = SessionHistoryService.parse(content: content, projectFallback: "/fallback")
        return parsed.bucketsByHour.values.first!
    }

    @Test("splits tokens per raw model id in a single hour bucket")
    func perRawModelSplit() {
        let content = [
            line(ts: "2026-07-01T10:05:00.000Z", model: "claude-sonnet-5", input: 100, output: 200, cacheRead: 50, cacheCreate: 10),
            line(ts: "2026-07-01T10:40:00.000Z", model: "claude-sonnet-4-6", input: 5, output: 7, cacheRead: 1, cacheCreate: 2),
            line(ts: "2026-07-01T10:50:00.000Z", model: "claude-opus-4-8", input: 1000, output: 2000)
        ].joined(separator: "\n")

        let parsed = SessionHistoryService.parse(content: content, projectFallback: "/fallback")
        #expect(parsed.bucketsByHour.count == 1)
        let bucket = parsed.bucketsByHour.values.first!

        // Each raw model id keeps its own breakdown, even though sonnet-5 and
        // sonnet-4-6 both fold to `.sonnet` for display.
        #expect(bucket.tokensByRawModelDetailed["claude-sonnet-5"]
            == TokenBreakdown(input: 100, output: 200, cacheRead: 50, cacheCreate: 10))
        #expect(bucket.tokensByRawModelDetailed["claude-sonnet-4-6"]
            == TokenBreakdown(input: 5, output: 7, cacheRead: 1, cacheCreate: 2))
        #expect(bucket.tokensByRawModelDetailed["claude-opus-4-8"]
            == TokenBreakdown(input: 1000, output: 2000, cacheRead: 0, cacheCreate: 0))
    }

    @Test("coarse ModelKind totals still track active tokens")
    func coarseTotalsUnaffected() {
        let content = [
            line(ts: "2026-07-01T10:05:00.000Z", model: "claude-sonnet-5", input: 100, output: 200),
            line(ts: "2026-07-01T10:40:00.000Z", model: "claude-sonnet-4-6", input: 5, output: 7)
        ].joined(separator: "\n")
        let bucket = onlyBucket(content)
        // Both sonnet versions fold into .sonnet: active = (100+200)+(5+7).
        #expect(bucket.tokensByModel[.sonnet] == 312)
        #expect(bucket.inputTokens == 105)
        #expect(bucket.outputTokens == 207)
    }

    @Test("the detailed breakdown accumulates repeated calls for the same model")
    func accumulatesSameModel() {
        let content = [
            line(ts: "2026-07-01T10:05:00.000Z", model: "claude-opus-4-8", input: 10, output: 20, cacheRead: 5, cacheCreate: 1),
            line(ts: "2026-07-01T10:06:00.000Z", model: "claude-opus-4-8", input: 30, output: 40, cacheRead: 5, cacheCreate: 3)
        ].joined(separator: "\n")
        let bucket = onlyBucket(content)
        #expect(bucket.tokensByRawModelDetailed["claude-opus-4-8"]
            == TokenBreakdown(input: 40, output: 60, cacheRead: 10, cacheCreate: 4))
    }

    @Test("lines without token usage are ignored")
    func ignoresNonUsageLines() {
        let content = [
            #"{"timestamp":"2026-07-01T10:05:00.000Z","type":"user","message":{"role":"user","content":"hi"}}"#,
            line(ts: "2026-07-01T10:06:00.000Z", model: "claude-opus-4-8", input: 10, output: 20)
        ].joined(separator: "\n")
        let bucket = onlyBucket(content)
        #expect(bucket.tokensByRawModelDetailed.count == 1)
        #expect(bucket.tokensByRawModelDetailed["claude-opus-4-8"]?.input == 10)
    }

    @Test("the per-raw split prices sonnet versions distinctly end-to-end")
    func breakdownPricesDistinctly() {
        let content = [
            line(ts: "2026-07-01T10:05:00.000Z", model: "claude-sonnet-5", input: 1_000_000, output: 0),
            line(ts: "2026-07-01T10:40:00.000Z", model: "claude-sonnet-4-6", input: 1_000_000, output: 0)
        ].joined(separator: "\n")
        let bucket = onlyBucket(content)
        let est = CostEstimator.estimate(
            breakdownByRawModel: bucket.tokensByRawModelDetailed,
            pricing: .fallback
        )
        // sonnet-5 @ $2 + sonnet-4-6 @ $3 = $5, both under the .sonnet kind.
        #expect(est.total == 5)
        #expect(est.perModel[.sonnet] == 5)
    }
}
