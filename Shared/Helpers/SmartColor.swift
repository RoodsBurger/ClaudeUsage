import Foundation

/// Smart-color risk model. Pure functional layer - no UI, no I/O,
/// no state. Tested directly in isolation (see `SmartColorTests`).
///
/// Invariants:
/// - `risk` is a continuous score in [0, 1] derived from three
///   independent sources (absolute, projection, pacing).
/// - Each source uses `smoothstep` for C1 continuity.
/// - Confidence weighting on the time-derived sources suppresses
///   early-window noise.
/// - The discrete zone (chill/onTrack/warning/hot) supports
///   optional hysteresis to prevent flicker around band boundaries.
enum SmartColor {

    // MARK: - Mathematical primitives

    /// Hermite-smoothed step function. Continuous (C1) clamp from a to b.
    /// Returns 0 when x <= a, 1 when x >= b, smoothly interpolated in between.
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard a < b else { return x >= b ? 1 : 0 }
        let t = max(0, min(1, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    /// Confidence in the rate estimate, growing from 0 to ~1 across the
    /// window. Used to dampen projection / pacing risk early when the
    /// rate computed from a few elapsed minutes is noisy. The growth
    /// rate `k` is profile-tunable.
    static func confidence(e: Double, k: Double = 5.0) -> Double {
        1 - exp(-k * max(0, e))
    }

    // MARK: - Risk components

    /// Component A - absolute risk: how close to the limit, irrespective
    /// of pacing. Drives the "98% must always feel red" property.
    static func absoluteRisk(u: Double, θw: Double, θc: Double) -> Double {
        smoothstep(θw, θc, u)
    }

    /// Component B - projection risk: at the current consumption rate,
    /// how much over the limit will we end the window? Saturates at the
    /// profile-defined `projUpper`. Weighted by confidence so a high
    /// rate computed from a few elapsed minutes doesn't scream.
    static func projectionRisk(u: Double, e: Double, params: SmartColorParameters = .default) -> Double {
        guard u > 0.0001, e > 0.0001 else { return 0 }
        let projected = u / e
        let raw = smoothstep(1.0, params.projUpper, projected)
        return raw * confidence(e: e, k: params.k)
    }

    /// Component C - pacing risk: gap between actual utilization and the
    /// linear pace. Only positive deltas (ahead of schedule) escalate.
    /// 0 inside the user's `m` margin, ramps to 1 as delta grows 15pp
    /// past m. Same confidence weighting as projection.
    static func pacingRisk(u: Double, e: Double, m: Double, params: SmartColorParameters = .default) -> Double {
        let delta = u - e
        let raw = smoothstep(m, m + 0.15, delta)
        return raw * confidence(e: e, k: params.k)
    }

    /// Combines the three components via `max`. The most conservative
    /// signal wins - none can mask another's red flag. Hard-caps at 1.0
    /// when utilization >= 100%.
    ///
    /// The absolute component uses the profile's `absoluteLower` /
    /// `absoluteUpper` smoothstep bounds and is dampened by projection
    /// health:
    ///
    /// ```text
    /// aRaw = smoothstep(params.absoluteLower, params.absoluteUpper, u)
    /// projectionHealth = smoothstep(0.7, 1.0, u / e)
    /// a = aRaw × projectionHealth
    /// ```
    ///
    /// At `u/e ≥ 1` (projected to overshoot), `projectionHealth` saturates
    /// to 1 and absolute fires at full strength. At `u/e ≤ 0.7` (projected
    /// well under), the multiplier drops to 0 and absolute is suppressed -
    /// keeping calm pacing on a high absolute from triggering a false alarm.
    ///
    /// Profile owns the smart calibration end-to-end. The user's threshold
    /// sliders only drive the threshold-mode fallback (when
    /// `smartColorEnabled == false`).
    static func combinedRisk(u: Double, e: Double, m: Double, params: SmartColorParameters = .default) -> Double {
        if u >= 1.0 { return 1.0 }
        let aRaw = smoothstep(params.absoluteLower, params.absoluteUpper, u)
        let projectionHealth: Double = {
            guard e > 0.0001 else { return 1.0 }
            return smoothstep(0.7, 1.0, u / e)
        }()
        let a = aRaw * projectionHealth
        let b = projectionRisk(u: u, e: e, params: params)
        let c = pacingRisk(u: u, e: e, m: m, params: params)
        return max(a, max(b, c))
    }

    /// End-to-end continuous risk score [0, 1] for a metric's utilization
    /// against its reset window. Falls back to absolute-only risk when
    /// there is no reset date / window to project against (e.g. the Extra
    /// Credits pool). Smart mode is profile-driven; user thresholds only
    /// apply to threshold mode (see `RiskZone.forPercent`).
    static func risk(
        utilization: Double,
        resetDate: Date?,
        windowDuration: TimeInterval,
        pacingMargin: Double = 10,
        now: Date = Date(),
        profile: SmartColorProfile = .default
    ) -> Double {
        if utilization >= 100 { return 1.0 }
        let u = max(0, utilization) / 100
        let params = profile.parameters

        guard let resetDate, windowDuration > 0 else {
            return absoluteRisk(u: u, θw: params.absoluteLower, θc: params.absoluteUpper)
        }

        let remaining = max(0, resetDate.timeIntervalSince(now))
        let t = min(1.0, remaining / windowDuration)
        let e = max(0.0, 1.0 - t)
        let m = pacingMargin / 100

        return combinedRisk(u: u, e: e, m: m, params: params)
    }

    // MARK: - Zone derivation

    /// Discrete zone for risk, with optional hysteresis. When `previous`
    /// is provided, transitions in the falling direction need an extra
    /// 5pp buffer to avoid flicker around a boundary.
    ///
    /// Rising thresholds (cold start):
    ///   chill < 0.30 <= onTrack < 0.55 <= warning < 0.78 <= hot
    ///
    /// Falling thresholds (held by previous zone):
    ///   keep hot until r < 0.73; keep warning until r < 0.50;
    ///   keep onTrack until r < 0.25.
    static func zoneForRisk(_ risk: Double, previous: PacingZone? = nil, params: SmartColorParameters = .default) -> PacingZone {
        let r = max(0, min(1, risk))
        let rising = (chill: params.chillThreshold, warning: params.warningThreshold, hot: params.hotThreshold)
        let falling = (chill: params.fallingChill, warning: params.fallingWarning, hot: params.fallingHot)

        guard let previous else {
            return zoneFromRising(r, rising: rising)
        }

        switch previous {
        case .chill:
            return zoneFromRising(r, rising: rising)
        case .onTrack:
            if r >= rising.hot     { return .hot }
            if r >= rising.warning { return .warning }
            if r <  falling.chill  { return .chill }
            return .onTrack
        case .warning:
            if r >= rising.hot     { return .hot }
            if r <  falling.chill  { return .chill }
            if r <  falling.warning { return .onTrack }
            return .warning
        case .hot:
            if r <  falling.chill   { return .chill }
            if r <  falling.warning { return .onTrack }
            if r <  falling.hot     { return .warning }
            return .hot
        }
    }

    private static func zoneFromRising(_ r: Double, rising: (chill: Double, warning: Double, hot: Double)) -> PacingZone {
        if r >= rising.hot     { return .hot }
        if r >= rising.warning { return .warning }
        if r >= rising.chill   { return .onTrack }
        return .chill
    }

    // MARK: - RiskZone mapping

    /// Maps continuous risk to the semantic `RiskZone` (ok/warning/critical)
    /// used everywhere a data point needs a color: resolves the 4-zone
    /// hysteresis result via `zoneForRisk`, then folds chill/onTrack into
    /// `.ok` (both read as "under control"), warning into `.warning`, and
    /// hot into `.critical`.
    static func riskZone(forRisk risk: Double, previous: PacingZone? = nil, params: SmartColorParameters = .default) -> RiskZone {
        switch zoneForRisk(risk, previous: previous, params: params) {
        case .chill, .onTrack: return .ok
        case .warning:         return .warning
        case .hot:              return .critical
        }
    }
}
