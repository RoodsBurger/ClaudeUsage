import Testing
import Foundation

@Suite("PacingCalculator.calculateMonthly")
struct PacingCalculatorMonthlyTests {

    /// Fixed UTC calendar so month boundaries never depend on the machine's
    /// locale or timezone.
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func pool(used: Double = 250, limit: Double = 500, utilization: Double? = nil, enabled: Bool = true) -> ExtraUsage {
        ExtraUsage(
            isEnabled: enabled, monthlyLimit: limit, usedCredits: used,
            utilization: utilization, currency: "USD", disabledReason: nil
        )
    }

    private func monthly(
        _ extra: ExtraUsage?,
        margin: Double = 10,
        now: Date,
        activeDays: Set<Int> = PacingSchedule.allDays,
        activeHours: (start: Int, end: Int)? = nil
    ) -> PacingResult? {
        PacingCalculator.calculateMonthly(
            extraUsage: extra, margin: margin, now: now,
            activeDays: activeDays, activeHours: activeHours,
            calendar: Self.calendar
        )
    }

    // MARK: - Nil gating

    @Test("nil pool, disabled pool, and non-positive limits all return nil")
    func nilGating() {
        let now = Self.date(2026, 6, 16)
        #expect(monthly(nil, now: now) == nil)
        #expect(monthly(Self.pool(enabled: false), now: now) == nil)
        #expect(monthly(ExtraUsage(isEnabled: true, monthlyLimit: nil, usedCredits: 10, utilization: nil, currency: "USD", disabledReason: nil), now: now) == nil)
        #expect(monthly(Self.pool(limit: 0), now: now) == nil)
    }

    // MARK: - Elapsed-month projection

    @Test("mid-month linear expectation: 50% spent at 50% elapsed is onTrack with delta 0")
    func midMonthOnTrack() throws {
        // June 2026 has 30 days -> June 16 00:00 is exactly 15/30 elapsed.
        let result = try #require(monthly(Self.pool(used: 250, limit: 500), now: Self.date(2026, 6, 16)))
        #expect(abs(result.expectedUsage - 50) < 0.001)
        #expect(abs(result.delta) < 0.001)
        #expect(result.zone == .onTrack)
        #expect(result.actualUsage == 50)
    }

    @Test("month start: expected 0, so 30% spent is hot")
    func monthStartIsHot() throws {
        let result = try #require(monthly(Self.pool(used: 150, limit: 500), now: Self.date(2026, 6, 1)))
        #expect(result.expectedUsage == 0)
        #expect(result.delta == 30)
        #expect(result.zone == .hot)
    }

    @Test("month end: expected approaches 100, so 50% spent is chill")
    func monthEndIsChill() throws {
        let result = try #require(monthly(Self.pool(used: 250, limit: 500), now: Self.date(2026, 6, 30, 23, 59)))
        #expect(result.expectedUsage > 99.9)
        #expect(result.zone == .chill)
    }

    @Test("expected fraction respects the real month length (28 vs 31 days)")
    func monthLengthAware() throws {
        // Feb 2026: 28 days -> Feb 15 00:00 = 14/28 = 50%.
        let feb = try #require(monthly(Self.pool(), now: Self.date(2026, 2, 15)))
        #expect(abs(feb.expectedUsage - 50) < 0.001)
        // July 2026: 31 days -> July 16 12:00 = 15.5/31 = 50%.
        let jul = try #require(monthly(Self.pool(), now: Self.date(2026, 7, 16, 12)))
        #expect(abs(jul.expectedUsage - 50) < 0.001)
    }

    @Test("resetDate is the start of the next calendar month")
    func resetDateIsNextMonthStart() throws {
        let result = try #require(monthly(Self.pool(), now: Self.date(2026, 6, 16)))
        #expect(result.resetDate == Self.date(2026, 7, 1))
        // December rolls over the year boundary.
        let december = try #require(monthly(Self.pool(), now: Self.date(2026, 12, 10)))
        #expect(december.resetDate == Self.date(2027, 1, 1))
    }

    // MARK: - Actual-usage inputs

    @Test("the API-provided utilization wins over used/limit")
    func utilizationFieldWins() throws {
        let result = try #require(monthly(Self.pool(used: 10, limit: 100, utilization: 80), now: Self.date(2026, 6, 16)))
        #expect(result.actualUsage == 80)
    }

    @Test("used/limit fallback when utilization is omitted")
    func usedOverLimitFallback() throws {
        let result = try #require(monthly(Self.pool(used: 30, limit: 60), now: Self.date(2026, 6, 16)))
        #expect(result.actualUsage == 50)
    }

    // MARK: - Margin ladder (same thresholds as the window pacing)

    @Test("delta +15 is warning at margin 10 but onTrack at margin 20")
    func marginLadder() throws {
        // 65% spent at 50% elapsed -> delta +15.
        let strict = try #require(monthly(Self.pool(used: 325, limit: 500), margin: 10, now: Self.date(2026, 6, 16)))
        #expect(strict.zone == .warning)
        let relaxed = try #require(monthly(Self.pool(used: 325, limit: 500), margin: 20, now: Self.date(2026, 6, 16)))
        #expect(relaxed.zone == .onTrack)
    }

    // MARK: - Workweek awareness

    @Test("Mon-Fri schedule: expected pace counts only weekdays of the month")
    func workweekExpectedPace() throws {
        // June 2026 starts on a Monday and has 22 weekdays. By Monday June 8
        // 00:00, exactly 5 active days (Jun 1-5) have elapsed.
        let result = try #require(monthly(
            Self.pool(), now: Self.date(2026, 6, 8),
            activeDays: PacingSchedule.workweek
        ))
        #expect(abs(result.expectedUsage - (5.0 / 22.0 * 100)) < 0.01)
    }

    @Test("Mon-Fri schedule: the expected pace freezes over a weekend")
    func workweekWeekendFreeze() throws {
        let saturday = try #require(monthly(
            Self.pool(), now: Self.date(2026, 6, 6),
            activeDays: PacingSchedule.workweek
        ))
        let monday = try #require(monthly(
            Self.pool(), now: Self.date(2026, 6, 8),
            activeDays: PacingSchedule.workweek
        ))
        #expect(abs(saturday.expectedUsage - monday.expectedUsage) < 0.001)
    }

    @Test("active hours narrow the pace within active days")
    func activeHoursNarrowPace() throws {
        // 9-18 on weekdays: by Tuesday June 2 09:00, exactly one active
        // 9h-slot (Monday) of June's 22 * 9h has elapsed.
        let result = try #require(monthly(
            Self.pool(), now: Self.date(2026, 6, 2, 9),
            activeDays: PacingSchedule.workweek,
            activeHours: (start: 9, end: 18)
        ))
        #expect(abs(result.expectedUsage - (1.0 / 22.0 * 100)) < 0.01)
    }

    @Test("workweek and calendar-time expectations diverge on the same instant")
    func workweekDivergesFromCalendarTime() throws {
        // Thursday June 4 00:00: calendar time has 3/30 days elapsed (10%),
        // the Mon-Fri schedule has 3 of June's 22 weekdays elapsed (~13.6%).
        let calendarTime = try #require(monthly(Self.pool(used: 70, limit: 500), now: Self.date(2026, 6, 4)))
        let workweek = try #require(monthly(
            Self.pool(used: 70, limit: 500), now: Self.date(2026, 6, 4),
            activeDays: PacingSchedule.workweek
        ))
        #expect(abs(calendarTime.expectedUsage - 10) < 0.001)
        #expect(abs(workweek.expectedUsage - (3.0 / 22.0 * 100)) < 0.01)
    }
}
