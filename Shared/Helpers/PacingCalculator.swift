import Foundation

enum PacingCalculator {
    /// Messages cycle through 3 variants per zone, picked deterministically from
    /// the absolute delta so the same metric does not flip wording on every refresh.
    /// Two surface families: short (5h session, sprint feel) and long (weekly,
    /// marathon feel). Sonnet/Design weekly buckets reuse the long set.
    private static let sessionMessages: [PacingZone: [String]] = [
        .chill:   ["pacing.session.chill.1", "pacing.session.chill.2", "pacing.session.chill.3"],
        .onTrack: ["pacing.session.ontrack.1", "pacing.session.ontrack.2", "pacing.session.ontrack.3"],
        .warning: ["pacing.session.warning.1", "pacing.session.warning.2", "pacing.session.warning.3"],
        .hot:     ["pacing.session.hot.1", "pacing.session.hot.2", "pacing.session.hot.3"],
    ]
    private static let weeklyMessages: [PacingZone: [String]] = [
        .chill:   ["pacing.weekly.chill.1", "pacing.weekly.chill.2", "pacing.weekly.chill.3"],
        .onTrack: ["pacing.weekly.ontrack.1", "pacing.weekly.ontrack.2", "pacing.weekly.ontrack.3"],
        .warning: ["pacing.weekly.warning.1", "pacing.weekly.warning.2", "pacing.weekly.warning.3"],
        .hot:     ["pacing.weekly.hot.1", "pacing.weekly.hot.2", "pacing.weekly.hot.3"],
    ]
    /// Monthly-budget flavor (enterprise org spend vs its monthly limit).
    private static let monthlyMessages: [PacingZone: [String]] = [
        .chill:   ["pacing.monthly.chill.1", "pacing.monthly.chill.2", "pacing.monthly.chill.3"],
        .onTrack: ["pacing.monthly.ontrack.1", "pacing.monthly.ontrack.2", "pacing.monthly.ontrack.3"],
        .warning: ["pacing.monthly.warning.1", "pacing.monthly.warning.2", "pacing.monthly.warning.3"],
        .hot:     ["pacing.monthly.hot.1", "pacing.monthly.hot.2", "pacing.monthly.hot.3"],
    ]

    static func calculate(from usage: UsageResponse, margin: Double = 10, now: Date = Date(), activeDays: Set<Int> = PacingSchedule.allDays, activeHours: (start: Int, end: Int)? = nil) -> PacingResult? {
        calculate(from: usage, bucket: .sevenDay, margin: margin, now: now, activeDays: activeDays, activeHours: activeHours)
    }

    static func calculate(from usage: UsageResponse, bucket: PacingBucket, margin: Double = 10, now: Date = Date(), activeDays: Set<Int> = PacingSchedule.allDays, activeHours: (start: Int, end: Int)? = nil) -> PacingResult? {
        let usageBucket: UsageBucket?
        switch bucket {
        case .fiveHour: usageBucket = usage.fiveHour
        case .sevenDay: usageBucket = usage.sevenDay
        case .sonnet: usageBucket = usage.sevenDaySonnet
        }
        return calculateForBucket(usageBucket, bucket: bucket, margin: margin, now: now, activeDays: activeDays, activeHours: activeHours)
    }

    static func calculateAll(from usage: UsageResponse, margin: Double = 10, now: Date = Date(), activeDays: Set<Int> = PacingSchedule.allDays, activeHours: (start: Int, end: Int)? = nil) -> [PacingBucket: PacingResult] {
        var results: [PacingBucket: PacingResult] = [:]
        for bucket in PacingBucket.allCases {
            if let result = calculate(from: usage, bucket: bucket, margin: margin, now: now, activeDays: activeDays, activeHours: activeHours) {
                results[bucket] = result
            }
        }
        return results
    }

    /// Monthly-budget pacing (enterprise): projects the Extra Usage pool's
    /// $used against its monthly limit over the elapsed fraction of the
    /// calendar month containing `now`. Workweek-aware: a restricted schedule
    /// makes only active days/hours advance the expected pace, exactly like
    /// the weekly buckets. Zones use the same ±margin ladder. Returns nil
    /// when the pool is absent, disabled, or has no positive limit.
    /// `PacingResult.resetDate` is the start of the next calendar month.
    static func calculateMonthly(
        extraUsage: ExtraUsage?,
        margin: Double = 10,
        now: Date = Date(),
        activeDays: Set<Int> = PacingSchedule.allDays,
        activeHours: (start: Int, end: Int)? = nil,
        calendar: Calendar = .current
    ) -> PacingResult? {
        guard let extraUsage, extraUsage.isEnabled,
              let limit = extraUsage.monthlyLimit, limit > 0 else { return nil }
        let used = extraUsage.usedCredits ?? 0
        let actual = extraUsage.utilization ?? (used / limit * 100)

        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart),
              monthEnd > monthStart else { return nil }

        let clampedNow = min(max(now, monthStart), monthEnd)
        let clampedElapsed: Double
        // A full 7-day set with no hour restriction is plain calendar time;
        // otherwise measure elapsed over the active days/hours only, so off
        // time doesn't advance the expected pace (same rule as the weeklies).
        let isFullWindow = activeDays.count >= 7 && activeHours == nil
        if isFullWindow {
            let duration = monthEnd.timeIntervalSince(monthStart)
            clampedElapsed = min(max(clampedNow.timeIntervalSince(monthStart) / duration, 0), 1)
        } else {
            let total = activeSeconds(from: monthStart, to: monthEnd, activeDays: activeDays, hours: activeHours, calendar: calendar)
            let elapsed = activeSeconds(from: monthStart, to: clampedNow, activeDays: activeDays, hours: activeHours, calendar: calendar)
            clampedElapsed = total > 0 ? min(max(elapsed / total, 0), 1) : 0
        }

        return result(
            actual: actual,
            expected: clampedElapsed * 100,
            margin: margin,
            messages: monthlyMessages,
            resetDate: monthEnd
        )
    }

    /// Active sub-intervals within `[from, to]`: the day-sized segments that fall
    /// on an active weekday, clipped to the active hours window when `hours` is
    /// set. `activeDays` uses Gregorian weekday numbers (1=Sunday ... 7=Saturday);
    /// `hours` is `(start, end)` in 24h local time (end == 24 means midnight).
    /// Hour bounds are resolved with `date(bySettingHour:)` so DST days (23h/25h)
    /// stay correct. Single source of truth for both `activeSeconds` and the
    /// off-time hatch ranges.
    static func activeIntervals(from: Date, to: Date, activeDays: Set<Int>, hours: (start: Int, end: Int)? = nil, calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        guard to > from else { return [] }
        var out: [(start: Date, end: Date)] = []
        var cursor = from
        // A 7-day window spans ~8 day-segments; the cap is a defensive backstop.
        var guardCount = 0
        while cursor < to && guardCount < 400 {
            guardCount += 1
            let dayStart = calendar.startOfDay(for: cursor)
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? to
            let segmentEnd = min(nextMidnight, to)
            if activeDays.contains(calendar.component(.weekday, from: cursor)) {
                if let hours {
                    let hStart = calendar.date(bySettingHour: hours.start, minute: 0, second: 0, of: dayStart) ?? dayStart
                    let hEnd = hours.end >= 24
                        ? nextMidnight
                        : (calendar.date(bySettingHour: hours.end, minute: 0, second: 0, of: dayStart) ?? nextMidnight)
                    let lo = max(cursor, hStart)
                    let hi = min(segmentEnd, hEnd)
                    if hi > lo { out.append((lo, hi)) }
                } else {
                    out.append((cursor, segmentEnd))
                }
            }
            cursor = segmentEnd
        }
        return out
    }

    /// Total active seconds within `[from, to]` (sum of `activeIntervals`).
    static func activeSeconds(from: Date, to: Date, activeDays: Set<Int>, hours: (start: Int, end: Int)? = nil, calendar: Calendar = .current) -> TimeInterval {
        activeIntervals(from: from, to: to, activeDays: activeDays, hours: hours, calendar: calendar)
            .reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
    }

    private static func calculateForBucket(_ usageBucket: UsageBucket?, bucket: PacingBucket, margin: Double = 10, now: Date = Date(), activeDays: Set<Int> = PacingSchedule.allDays, activeHours: (start: Int, end: Int)? = nil) -> PacingResult? {
        guard let usageBucket, let resetsAt = usageBucket.resetsAtDate else { return nil }

        let duration = bucket.periodDuration
        let startOfPeriod = resetsAt.addingTimeInterval(-duration)

        let clampedElapsed: Double
        // The 5h session is an intraday window (never schedule-adjusted), and a
        // full 7-day set with no hour restriction is identical to the classic
        // calc - keep the cheap path for both. Otherwise measure elapsed over the
        // active days/hours only, so off time doesn't advance the expected pace.
        let isFullWindow = activeDays.count >= 7 && activeHours == nil
        if bucket == .fiveHour || isFullWindow {
            let elapsed = now.timeIntervalSince(startOfPeriod) / duration
            clampedElapsed = min(max(elapsed, 0), 1)
        } else {
            let total = activeSeconds(from: startOfPeriod, to: resetsAt, activeDays: activeDays, hours: activeHours)
            let elapsedEnd = min(max(now, startOfPeriod), resetsAt)
            let elapsed = activeSeconds(from: startOfPeriod, to: elapsedEnd, activeDays: activeDays, hours: activeHours)
            clampedElapsed = total > 0 ? min(max(elapsed / total, 0), 1) : 0
        }

        return result(
            actual: usageBucket.utilization,
            expected: clampedElapsed * 100,
            margin: margin,
            messages: bucket == .fiveHour ? sessionMessages : weeklyMessages,
            resetDate: resetsAt
        )
    }

    /// Shared tail for every pacing flavor (session / weekly / monthly):
    /// 4-zone pacing -> chill / onTrack (within ±margin) / warning
    /// (margin..2*margin) / hot (>2*margin). The pacingMargin slider drives
    /// both thresholds so a single user-facing setting controls the whole
    /// sensitivity curve. The message cycles deterministically through the
    /// zone's pool, keyed by the absolute delta.
    private static func result(
        actual: Double,
        expected: Double,
        margin: Double,
        messages: [PacingZone: [String]],
        resetDate: Date?
    ) -> PacingResult {
        let delta = actual - expected

        let zone: PacingZone
        if delta < -margin {
            zone = .chill
        } else if delta <= margin {
            zone = .onTrack
        } else if delta <= margin * 2 {
            zone = .warning
        } else {
            zone = .hot
        }

        let pool = messages[zone] ?? []
        let index = pool.isEmpty ? 0 : abs(Int(delta)) % pool.count
        let messageKey = pool.isEmpty ? "" : pool[index]
        let message = messageKey.isEmpty ? "" : String(localized: String.LocalizationValue(messageKey))

        return PacingResult(
            delta: delta,
            expectedUsage: expected,
            actualUsage: actual,
            zone: zone,
            message: message,
            resetDate: resetDate
        )
    }
}
