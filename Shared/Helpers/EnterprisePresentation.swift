import Foundation

/// Pure presentation rules for enterprise-aware surfaces - no I/O, no stores,
/// fully unit-testable.
///
/// Enterprise orgs commonly return the 5h/weekly/Sonnet windows frozen at
/// utilization 0 with no reset timestamp: the usage API does not track those
/// windows for them (the dashboard would read "RESETS IN -" forever). The
/// detection is data-driven (reset timestamp absent + zero utilization), never
/// plan-hardcoded: a personal account with a missing field keeps its tiles,
/// and an enterprise org that later gains tracking shows them again.
enum EnterprisePresentation {
    /// A window is tracked when the API reports a reset timestamp for it, or
    /// any non-zero utilization. An absent bucket is untracked.
    static func isTracked(_ bucket: UsageBucket?) -> Bool {
        guard let bucket else { return false }
        return bucket.resetsAt != nil || bucket.utilization > 0
    }

    /// Whether a usage-window tile renders on the dashboard grid. Hiding
    /// requires BOTH enterprise and untracked - plan type alone never hides,
    /// and non-enterprise plans always render every tile exactly as before.
    static func showsWindowTile(planType: PlanType, bucket: UsageBucket?) -> Bool {
        planType != .enterprise || isTracked(bucket)
    }

    /// Enterprise replaces the session hero with the org-spend hero, but only
    /// when the spend pool actually reports data (`isEnabled`). Everything
    /// else keeps the session hero.
    static func usesSpendHero(planType: PlanType, extraUsage: ExtraUsage?) -> Bool {
        planType == .enterprise && extraUsage?.isEnabled == true
    }

    /// The dashboard's bottom spend card: redundant with the spend hero on
    /// enterprise, kept everywhere else (still gated on the pool being enabled).
    static func showsSpendCard(planType: PlanType, extraUsage: ExtraUsage?) -> Bool {
        extraUsage?.isEnabled == true && !usesSpendHero(planType: planType, extraUsage: extraUsage)
    }
}
