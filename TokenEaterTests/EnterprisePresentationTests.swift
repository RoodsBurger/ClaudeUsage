import Testing
import Foundation

/// Covers the pure enterprise-presentation rules: data-driven untracked-window
/// detection, tile visibility, and the spend hero / spend card split. These
/// helpers carry the whole enterprise path, which cannot be live-tested on a
/// personal (MAX) account.
@Suite("EnterprisePresentation")
struct EnterprisePresentationTests {

    /// The exact shape enterprise orgs return for untracked windows:
    /// utilization 0, no resets_at ("RESETS IN -" on the dashboard).
    private let untracked = UsageBucket(utilization: 0, resetsAt: nil)
    private let trackedIdle = UsageBucket(utilization: 0, resetsAt: "2026-07-14T12:00:00Z")
    private let trackedBusy = UsageBucket(utilization: 99, resetsAt: "2026-07-14T12:00:00Z")
    /// Defensive shape: usage reported but no reset timestamp - still tracked.
    private let busyNoReset = UsageBucket(utilization: 12, resetsAt: nil)

    private let nonEnterprisePlans: [PlanType] = [.pro, .max, .team, .free, .unknown]

    // MARK: - isTracked (data-driven, never plan-driven)

    @Test("a bucket with a reset timestamp is tracked, even at 0% utilization")
    func resetTimestampMeansTracked() {
        #expect(EnterprisePresentation.isTracked(trackedIdle) == true)
        #expect(EnterprisePresentation.isTracked(trackedBusy) == true)
    }

    @Test("non-zero utilization means tracked even without a reset timestamp")
    func utilizationMeansTracked() {
        #expect(EnterprisePresentation.isTracked(busyNoReset) == true)
    }

    @Test("0% with no reset timestamp is untracked - the enterprise frozen-window shape")
    func zeroAndNoResetIsUntracked() {
        #expect(EnterprisePresentation.isTracked(untracked) == false)
    }

    @Test("an absent bucket is untracked")
    func absentBucketIsUntracked() {
        #expect(EnterprisePresentation.isTracked(nil) == false)
    }

    // MARK: - showsWindowTile

    @Test("non-enterprise plans always show window tiles, whatever the bucket looks like")
    func nonEnterpriseAlwaysShowsTiles() {
        for plan in nonEnterprisePlans {
            for bucket in [untracked, trackedIdle, trackedBusy, busyNoReset, nil] {
                #expect(
                    EnterprisePresentation.showsWindowTile(planType: plan, bucket: bucket) == true,
                    "plan \(plan), bucket \(String(describing: bucket?.utilization))"
                )
            }
        }
    }

    @Test("enterprise shows a tracked window tile")
    func enterpriseShowsTracked() {
        #expect(EnterprisePresentation.showsWindowTile(planType: .enterprise, bucket: trackedIdle) == true)
        #expect(EnterprisePresentation.showsWindowTile(planType: .enterprise, bucket: trackedBusy) == true)
        #expect(EnterprisePresentation.showsWindowTile(planType: .enterprise, bucket: busyNoReset) == true)
    }

    @Test("enterprise hides an untracked window tile")
    func enterpriseHidesUntracked() {
        #expect(EnterprisePresentation.showsWindowTile(planType: .enterprise, bucket: untracked) == false)
        #expect(EnterprisePresentation.showsWindowTile(planType: .enterprise, bucket: nil) == false)
    }

    // MARK: - Spend hero vs spend card

    private let enabledPool = ExtraUsage(
        isEnabled: true, monthlyLimit: 50_000, usedCredits: 29_848,
        utilization: 59.7, currency: "USD", disabledReason: nil
    )
    private let disabledPool = ExtraUsage(
        isEnabled: false, monthlyLimit: nil, usedCredits: nil,
        utilization: nil, currency: nil, disabledReason: "org_level_disabled"
    )

    @Test("enterprise with an enabled pool uses the spend hero and drops the bottom card")
    func enterpriseSpendHero() {
        #expect(EnterprisePresentation.usesSpendHero(planType: .enterprise, extraUsage: enabledPool) == true)
        #expect(EnterprisePresentation.showsSpendCard(planType: .enterprise, extraUsage: enabledPool) == false)
    }

    @Test("enterprise without pool data keeps the session hero and shows no card")
    func enterpriseNoPoolNoHero() {
        for pool in [disabledPool, nil] {
            #expect(EnterprisePresentation.usesSpendHero(planType: .enterprise, extraUsage: pool) == false)
            #expect(EnterprisePresentation.showsSpendCard(planType: .enterprise, extraUsage: pool) == false)
        }
    }

    @Test("non-enterprise plans never get the spend hero; the bottom card follows isEnabled")
    func nonEnterpriseKeepsCard() {
        for plan in nonEnterprisePlans {
            #expect(EnterprisePresentation.usesSpendHero(planType: plan, extraUsage: enabledPool) == false, "\(plan)")
            #expect(EnterprisePresentation.showsSpendCard(planType: plan, extraUsage: enabledPool) == true, "\(plan)")
            #expect(EnterprisePresentation.showsSpendCard(planType: plan, extraUsage: disabledPool) == false, "\(plan)")
            #expect(EnterprisePresentation.showsSpendCard(planType: plan, extraUsage: nil) == false, "\(plan)")
        }
    }
}

/// Enterprise-aware Extra Credits labels (menu bar prefix + display label).
@Suite("MetricID enterprise labels")
struct MetricIDEnterpriseLabelTests {

    @Test("Extra Credits short label reads Org on enterprise, EC elsewhere")
    func shortLabelRename() {
        #expect(MetricID.extraCredits.shortLabel(isEnterprise: true) == "Org")
        #expect(MetricID.extraCredits.shortLabel(isEnterprise: false) == "EC")
    }

    @Test("every other metric's short label ignores the enterprise flag")
    func shortLabelOthersUnchanged() {
        for metric in MetricID.allCases where metric != .extraCredits {
            #expect(metric.shortLabel(isEnterprise: true) == metric.shortLabel, "\(metric)")
        }
    }

    @Test("Extra Credits display label switches on enterprise only")
    func displayLabelRename() {
        let enterprise = MetricID.extraCredits.label(planType: .enterprise)
        #expect(!enterprise.isEmpty)
        #expect(enterprise != MetricID.extraCredits.label)
        for plan in [PlanType.pro, .max, .team, .free, .unknown] {
            #expect(MetricID.extraCredits.label(planType: plan) == MetricID.extraCredits.label, "\(plan)")
        }
    }

    @Test("every other metric's display label ignores the plan type")
    func displayLabelOthersUnchanged() {
        for metric in MetricID.allCases where metric != .extraCredits {
            #expect(metric.label(planType: .enterprise) == metric.label, "\(metric)")
        }
    }
}
