import SwiftUI

/// Stats space -> tile-based dashboard.
///
/// Layout follows the CleanMyMac X language : a prominent hero tile carrying
/// the dominant session metric, a grid of secondary metric tiles, a pacing
/// signal row, and an optional extra-usage card. Every surface is an opaque
/// `DS.Pastel.card` fill with a `DS.Pastel.border` hairline - no material, no
/// gradient wash, no glow - while the gauge/pacing colors flow from
/// `GaugeColorResolver` / `RiskZone` / `PacingZone.semanticColor` so every
/// data point uses the same pastel semantic system.
struct MonitoringView: View {
    @EnvironmentObject private var usageStore: UsageStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var vendorStatusStore: VendorStatusStore

    /// Lightweight 7d daily-buckets store for the inline tile insights.
    /// Loaded once on appear, refreshed if older than 60s. Owned by
    /// `MainAppView` so the cache survives navigation between spaces.
    @ObservedObject var insightsStore: MonitoringInsightsStore

    @State private var lastUpdateText = ""
    @State private var heroHover = false
    @State private var refreshHovering = false
    /// Toggled by tapping the hero tile - inline-reveals the pacing graph
    /// below the front content instead of flipping to a back face. The hero
    /// tile is a standalone full-width card, so its expand state stays
    /// independent of the secondary tile grid below.
    @State private var heroExpanded: Bool = false
    /// Single shared expand flag for every secondary metric tile
    /// (Weekly/Sonnet/Design/...). Tapping any tile toggles this one flag,
    /// so the whole grid expands or collapses in unison and every tile in a
    /// row always matches its row's tallest sibling height.
    @State private var tilesExpanded: Bool = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                header
                if vendorStatusStore.isDegraded, let status = vendorStatusStore.claudeStatus {
                    outageCard(status)
                }
                // Enterprise swaps the session hero for the org-spend hero
                // (the 5h window is typically untracked there and the spend
                // pool is the metric that matters). Everyone else keeps the
                // session hero unchanged.
                if let extra = usageStore.extraUsage,
                   EnterprisePresentation.usesSpendHero(planType: usageStore.planType, extraUsage: extra) {
                    spendHeroTile(extra)
                } else {
                    heroTile
                }
                metricsGrid
                pacingRow
                // The bottom spend card is redundant with the spend hero on
                // enterprise; every other plan keeps it (gated on isEnabled).
                if let extra = usageStore.extraUsage,
                   EnterprisePresentation.showsSpendCard(planType: usageStore.planType, extraUsage: extra) {
                    extraUsageTile(extra)
                }
                footerPills
            }
            .padding(DS.Spacing.md)
        }
        .task {
            refreshLastUpdateText()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                refreshLastUpdateText()
            }
        }
        .onAppear { insightsStore.warmIfStale() }
        .onChange(of: usageStore.lastUpdate) { _, _ in refreshLastUpdateText() }
    }

    /// Maps a tile id to the matching `ModelFamily` (nil = all-models).
    /// `design` / `cowork` map to nil because they're not present in
    /// the JSONL stream that `SessionHistoryService` aggregates - they
    /// fall back to the minimal inline content.
    private func tileFamily(for id: String) -> ModelFamily? {
        switch id {
        case "sonnet": return .sonnet
        case "opus":   return .opus
        case "weekly": return nil
        default:       return nil
        }
    }

    /// True only for tiles whose family is represented in the JSONL data
    /// (weekly, sonnet, opus). Design / Cowork get the simple fallback.
    private func hasRichBack(tileId: String) -> Bool {
        ["weekly", "sonnet", "opus"].contains(tileId)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                Text("RaiUsage")
                    .font(DS.Typography.title1)
                    .foregroundStyle(.primary)
            }

            if usageStore.planType != .unknown {
                Text(usageStore.planType.displayLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                            .fill(DS.Pastel.green.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                                    .stroke(DS.Pastel.green.opacity(0.4), lineWidth: 0.6)
                            )
                    )
            }

            Spacer()

            if usageStore.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            }

            if !lastUpdateText.isEmpty {
                Text(String(format: String(localized: "menubar.updated"), lastUpdateText))
                    .font(DS.Typography.label)
                    .foregroundStyle(.tertiary)
            }

            Button {
                Task { await usageStore.refresh(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(refreshHovering ? DS.Pastel.blue : Color.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(refreshHovering
                                  ? DS.Pastel.blue.opacity(0.18)
                                  : DS.Pastel.card)
                            .overlay(
                                Circle().stroke(
                                    refreshHovering
                                        ? DS.Pastel.blue.opacity(0.5)
                                        : DS.Pastel.border,
                                    lineWidth: 1
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "contextmenu.refresh"))
            .onHover { hovering in
                withAnimation(DS.Motion.springSnap) { refreshHovering = hovering }
            }
        }
        .padding(.horizontal, DS.Spacing.xs)
    }

    // MARK: - Hero tile (Session 5H)

    private var heroTile: some View {
        let pct = usageStore.fiveHourPct
        let resetDate = usageStore.lastUsage?.fiveHour?.resetsAtDate
        let gaugeColor = gaugeColor(pct: pct, resetDate: resetDate, windowDuration: 5 * 3600)
        let gaugeGradient = gaugeGradient(pct: pct, resetDate: resetDate, windowDuration: 5 * 3600)
        let zone = usageStore.fiveHourPacing?.zone
        let pacing = usageStore.fiveHourPacing
        // Ambient accent follows the gauge color so the number, ring, and
        // hover border all read as a single signal.
        let accent = gaugeColor
        let border = heroHover ? accent.opacity(0.4) : DS.Pastel.border

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { heroExpanded.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                heroFrontContent(pct: pct, gaugeColor: gaugeColor, gaugeGradient: gaugeGradient)

                if heroExpanded {
                    Rectangle()
                        .fill(DS.Pastel.border)
                        .frame(height: 1)
                    heroPacingSection(zone: zone, pacing: pacing)
                }

                heroDisclosureRow
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 200, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                    .fill(DS.Pastel.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
        }
        .buttonStyle(CardPressStyle(isHovered: heroHover, accent: accent, cornerRadius: DS.Radius.cardLg))
        .onHover { hovering in
            withAnimation(DS.Motion.springSnap) { heroHover = hovering }
        }
    }

    @ViewBuilder
    private func heroFrontContent(pct: Int, gaugeColor: Color, gaugeGradient: LinearGradient) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            // Left -> labels + meta
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.xs) {
                    Circle()
                        .fill(gaugeColor)
                        .frame(width: 6, height: 6)
                    Text(String(localized: "dashboard.hero.session.label").uppercased())
                        .font(DS.Typography.micro)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(pct)")
                        .font(.system(size: 64, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(gaugeColor)
                        .contentTransition(.numericText(value: Double(pct)))
                        .animation(DS.Motion.easeInOut, value: pct)
                    Text("%")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(gaugeColor.opacity(0.55))
                        .baselineOffset(5)
                }

                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "dashboard.hero.resetsIn").uppercased())
                        .font(DS.Typography.micro)
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                    Text(usageStore.fiveHourReset.isEmpty ? "-" : usageStore.fiveHourReset)
                        .font(DS.Typography.metricInline)
                        .foregroundStyle(.primary)
                    if let resetDate = usageStore.lastUsage?.fiveHour?.resetsAtDate {
                        Text("·")
                            .font(DS.Typography.metricInline)
                            .foregroundStyle(.tertiary.opacity(0.5))
                        Text(resetDate.formatted(.dateTime.hour().minute()))
                            .font(DS.Typography.metricInline)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right -> clean ring, no center glyph. The big % carries the meaning.
            RingGauge(
                percentage: pct,
                gradient: gaugeGradient,
                size: 140
            )
            .frame(width: 160, height: 160)
        }
    }

    /// Inline pacing detail, revealed below the front content when the hero
    /// is expanded. Left as a simple vertical stack (subtitle + delta, the
    /// pacing graph, the zone label) - no flip, no blur.
    @ViewBuilder
    private func heroPacingSection(zone: PacingZone?, pacing: PacingResult?) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Text((String(localized: "dashboard.hero.session.label") + " · " + String(localized: "pacing.label")).uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let pacing {
                    Text(String(format: "%+.1f%%", pacing.delta))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(pacing.zone.semanticColor)
                        .monospacedDigit()
                }
            }

            if let pacing {
                HeroPacingGraph(
                    actualUsage: pacing.actualUsage,
                    expectedUsage: pacing.expectedUsage,
                    deltaColor: pacing.zone.semanticColor,
                    trajectoryColor: pacing.zone.semanticColor
                )
                .frame(maxWidth: .infinity)
                .frame(height: 92)

                if let zone {
                    HStack(spacing: 6) {
                        Image(systemName: zoneGlyph(for: zone))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(zone.semanticColor)
                        Text(zoneLabel(zone).uppercased())
                            .font(.system(size: 10, weight: .medium))
                            .tracking(1)
                            .foregroundStyle(zone.semanticColor)
                    }
                }
            } else {
                Text("Pacing data unavailable")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Small always-visible affordance signalling the hero tile can expand
    /// to reveal the pacing graph. Icon-only state swap - no rotation.
    private var heroDisclosureRow: some View {
        HStack(spacing: 4) {
            Image(systemName: heroExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
            Text(String(localized: "pacing.label"))
                .font(DS.Typography.micro)
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - Hero tile (enterprise org spend)

    /// Enterprise hero: the org's monthly spend pool replaces the session
    /// ring. Reuses the extra-credits data and the same windowless threshold
    /// ladder as the bottom spend card, so the color always agrees with the
    /// menu bar and popover.
    private func spendHeroTile(_ extra: ExtraUsage) -> some View {
        let used = extra.usedCredits ?? 0
        let limit = extra.monthlyLimit ?? 0
        let pct = extra.percent
        let currency = extra.currency ?? "USD"
        let tint = RiskZone.forPercent(pct, thresholds: settingsStore.thresholds).color
        let usedText = CurrencyFormatter.formatMinorUnits(used, currencyCode: currency, locale: Locale(identifier: "en_US"))
        let limitText = CurrencyFormatter.formatMinorUnits(limit, currencyCode: currency, locale: Locale(identifier: "en_US"))

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.xs) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(String(localized: "metric.orgUsage").uppercased())
                    .font(DS.Typography.micro)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                Text(usedText)
                    .font(.system(size: 48, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: used))
                    .animation(DS.Motion.easeInOut, value: used)
                if limit > 0 {
                    Text(String(localized: "dashboard.extra.separator"))
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(limitText)
                        .font(.system(size: 22, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Pastel.track)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint)
                            .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                    }
                }
                .frame(height: 6)
                HStack(spacing: DS.Spacing.xs) {
                    Text("\(pct)%")
                        .font(DS.Typography.metricInline)
                        .monospacedDigit()
                        .foregroundStyle(tint)
                    Spacer()
                    Text(String(localized: "dashboard.extra.monthly"))
                        .font(DS.Typography.label)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(String(localized: "dashboard.extra.noLimit"))
                    .font(DS.Typography.label)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                .fill(DS.Pastel.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.cardLg, style: .continuous)
                .stroke(DS.Pastel.border, lineWidth: 1)
        )
    }

    // MARK: - Metrics grid

    private var metricsGrid: some View {
        // Width-filling rows instead of a fixed 3-column grid: the number of
        // secondary tiles varies (Design/Opus/Cowork are shown only when their
        // API bucket exists), so a fixed grid left an empty trailing cell when
        // the count was not a multiple of 3. Each row's tiles stretch to fill
        // the full width, so there is never a hole regardless of tile count.
        // Every tile shares `tilesExpanded`, so tapping any one of them
        // expands the whole grid together, and each tile's `maxHeight:
        // .infinity` frame stretches it to match its row's tallest sibling -
        // collapsed or expanded, a row's tiles are always the same height.
        let rows = MetricsGridLayout.rows(secondaryTiles)
        return VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    ForEach(row, id: \.id) { tile in
                        MetricTile(
                            id: tile.id,
                            label: tile.label,
                            icon: tile.icon,
                            pct: tile.pct,
                            resetText: tile.resetText,
                            resetDate: tile.resetDate,
                            windowDuration: tile.windowDuration,
                            smartEnabled: settingsStore.smartColorEnabled,
                            pacingMargin: Double(settingsStore.pacingMargin),
                            smartProfile: settingsStore.smartColorProfile,
                            thresholds: settingsStore.thresholds,
                            insights: hasRichBack(tileId: tile.id)
                                ? insightsStore.snapshot(for: tileFamily(for: tile.id))
                                : nil,
                            insightsLoaded: insightsStore.hasLoaded,
                            expanded: tilesExpanded,
                            onToggle: { tilesExpanded.toggle() }
                        )
                    }
                }
            }
        }
    }

    private var secondaryTiles: [TileDescriptor] {
        let weekWindow: TimeInterval = 7 * 86_400
        let plan = usageStore.planType
        var tiles: [TileDescriptor] = []
        // On enterprise the spend hero replaces the session hero, so a TRACKED
        // 5h window re-enters the grid as a normal tile; untracked stays hidden.
        // Non-enterprise never reaches this branch - the session data lives in
        // the hero there, exactly as before.
        if EnterprisePresentation.usesSpendHero(planType: plan, extraUsage: usageStore.extraUsage),
           EnterprisePresentation.isTracked(usageStore.lastUsage?.fiveHour) {
            tiles.append(TileDescriptor(
                id: "session",
                label: String(localized: "metric.session"),
                icon: "clock.fill",
                pct: usageStore.fiveHourPct,
                resetText: usageStore.fiveHourReset.isEmpty ? nil : usageStore.fiveHourReset,
                resetDate: usageStore.lastUsage?.fiveHour?.resetsAtDate,
                windowDuration: 5 * 3600
            ))
        }
        // Window tiles hide only when enterprise AND untracked (no reset
        // timestamp, zero utilization) - see EnterprisePresentation. Every
        // other plan keeps every tile unconditionally, as before.
        if EnterprisePresentation.showsWindowTile(planType: plan, bucket: usageStore.lastUsage?.sevenDay) {
            tiles.append(TileDescriptor(
                id: "weekly",
                label: String(localized: "metric.weekly"),
                icon: "calendar",
                pct: usageStore.sevenDayPct,
                resetText: usageStore.sevenDayReset,
                resetDate: usageStore.lastUsage?.sevenDay?.resetsAtDate,
                windowDuration: weekWindow
            ))
        }
        if EnterprisePresentation.showsWindowTile(planType: plan, bucket: usageStore.lastUsage?.sevenDaySonnet) {
            tiles.append(TileDescriptor(
                id: "sonnet",
                label: String(localized: "metric.sonnet"),
                icon: "text.quote",
                pct: usageStore.sonnetPct,
                resetText: usageStore.sonnetReset.isEmpty ? nil : usageStore.sonnetReset,
                resetDate: usageStore.lastUsage?.sevenDaySonnet?.resetsAtDate,
                windowDuration: weekWindow
            ))
        }
        if usageStore.hasDesign,
           EnterprisePresentation.showsWindowTile(planType: plan, bucket: usageStore.lastUsage?.sevenDayDesign) {
            tiles.append(TileDescriptor(
                id: "design",
                label: String(localized: "metric.design"),
                icon: "paintbrush.pointed.fill",
                pct: usageStore.designPct,
                resetText: usageStore.designReset.isEmpty ? nil : usageStore.designReset,
                resetDate: usageStore.lastUsage?.sevenDayDesign?.resetsAtDate,
                windowDuration: weekWindow
            ))
        }
        if usageStore.hasOpus,
           EnterprisePresentation.showsWindowTile(planType: plan, bucket: usageStore.lastUsage?.sevenDayOpus) {
            tiles.append(TileDescriptor(
                id: "opus",
                label: "Opus",
                icon: "brain.head.profile",
                pct: usageStore.opusPct,
                resetText: nil,
                resetDate: nil,
                windowDuration: weekWindow
            ))
        }
        if usageStore.hasCowork,
           EnterprisePresentation.showsWindowTile(planType: plan, bucket: usageStore.lastUsage?.sevenDayCowork) {
            tiles.append(TileDescriptor(
                id: "cowork",
                label: "Cowork",
                icon: "person.2.fill",
                pct: usageStore.coworkPct,
                resetText: nil,
                resetDate: nil,
                windowDuration: weekWindow
            ))
        }
        if usageStore.hasFable,
           EnterprisePresentation.showsWindowTile(planType: plan, bucket: usageStore.lastUsage?.sevenDayFable) {
            tiles.append(TileDescriptor(
                id: "fable",
                label: String(localized: "metric.fable"),
                icon: "books.vertical.fill",
                pct: usageStore.fablePct,
                resetText: usageStore.fableReset.isEmpty ? nil : usageStore.fableReset,
                resetDate: usageStore.lastUsage?.sevenDayFable?.resetsAtDate,
                windowDuration: weekWindow
            ))
        }
        return tiles
    }

    // MARK: - Pacing row

    private var pacingRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let pacing = usageStore.fiveHourPacing {
                pacingCard(pacing: pacing, label: String(localized: "pacing.session.label"), icon: "clock.fill")
                    .frame(maxWidth: .infinity)
            }
            if let pacing = usageStore.pacingResult {
                pacingCard(pacing: pacing, label: String(localized: "pacing.weekly.label"), icon: "calendar.badge.clock", showWorkweekBadge: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func pacingCard(pacing: PacingResult, label: String, icon: String, showWorkweekBadge: Bool = false) -> some View {
        let tint = pacing.zone.semanticColor
        let sign = pacing.delta >= 0 ? "+" : ""
        let schedule = settingsStore.pacingSchedule
        let offRanges: [ClosedRange<Double>] = (showWorkweekBadge && schedule.isActive)
            ? (pacing.resetDate.map { schedule.offDayRanges(resetDate: $0) } ?? [])
            : []
        let nowInOffDay = showWorkweekBadge && schedule.isOffDay(Date())
        // Calendar-time position for the "now" marker so it aligns with the
        // off-day hatch (#194). nil keeps the active-time expected position.
        let markerFraction: Double? = (showWorkweekBadge && schedule.isActive)
            ? pacing.resetDate.map { schedule.nowFraction(resetDate: $0) }
            : nil
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.xs) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                        Text(label.uppercased())
                            .font(DS.Typography.micro)
                            .tracking(1.4)
                            .foregroundStyle(.secondary)
                        if showWorkweekBadge {
                            WorkweekBadge(schedule: settingsStore.pacingSchedule)
                        }
                    }
                    HStack(spacing: DS.Spacing.xxs) {
                        Circle()
                            .fill(tint)
                            .frame(width: 5, height: 5)
                        Text(zoneLabel(pacing.zone))
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.2)
                            .foregroundStyle(tint)
                    }
                }
                Spacer()
                Text("\(sign)\(Int(pacing.delta))%")
                    .font(.system(size: 28, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(value: pacing.delta))
                    .animation(DS.Motion.easeInOut, value: pacing.delta)
            }

            pacingTrack(actual: pacing.actualUsage, expected: pacing.expectedUsage, tint: tint, offDayRanges: offRanges, nowInOffDay: nowInOffDay, markerFraction: markerFraction)

            if !pacing.message.isEmpty {
                Text(pacing.message)
                    .font(DS.Typography.label)
                    .foregroundStyle(tint.opacity(0.85))
                    .lineLimit(1)
            } else {
                Text(" ")
                    .font(DS.Typography.label)
                    .foregroundStyle(.clear)
                    .lineLimit(1)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Pastel.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(tint.opacity(0.35), lineWidth: 1)
        )
    }

    private func pacingTrack(actual: Double, expected: Double, tint: Color, offDayRanges: [ClosedRange<Double>] = [], nowInOffDay: Bool = false, markerFraction: Double? = nil) -> some View {
        let clampedActual = min(max(actual, 0), 100)
        let clampedExpected = min(max(expected, 0), 100)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(DS.Pastel.track)
                    .frame(height: 6)
                if !offDayRanges.isEmpty {
                    OffDayHatch(ranges: offDayRanges, cornerRadius: 3)
                        .frame(height: 6)
                }
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(clampedActual) / 100, height: 6)
                Rectangle()
                    .fill(Color.primary.opacity(nowInOffDay ? 0.4 : 0.85))
                    .frame(width: 2, height: 12)
                    .offset(x: (markerFraction.map { geo.size.width * CGFloat(min(max($0, 0), 1)) } ?? (geo.size.width * CGFloat(clampedExpected) / 100)) - 1, y: -3)
            }
        }
        .frame(height: 12)
        .animation(DS.Motion.easeInOut, value: actual)
        .animation(DS.Motion.easeInOut, value: expected)
    }

    // MARK: - Service status

    private func outageCard(_ status: VendorStatus) -> some View {
        let tint = status.health == .down ? DS.Pastel.coral : DS.Pastel.amber
        let title = status.health == .down
            ? String(localized: "dashboard.status.down")
            : String(localized: "dashboard.status.degraded")
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(DS.Typography.title2)
                    .foregroundStyle(.primary)
                Spacer()
                Link(String(localized: "status.banner.view"), destination: status.statusPageURL)
                    .font(DS.Typography.label)
                    .foregroundStyle(tint)
            }
            if let incident = status.activeIncidents.first {
                Text(incident.name)
                    .font(DS.Typography.label)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !status.affectedComponents.isEmpty {
                Text(String(format: String(localized: "dashboard.status.affected"),
                            status.affectedComponents.joined(separator: ", ")))
                    .font(DS.Typography.label)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Pastel.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Extra usage

    private func extraUsageTile(_ extra: ExtraUsage) -> some View {
        let used = extra.usedCredits ?? 0
        let limit = extra.monthlyLimit ?? 0
        let pct = extra.utilization.map { Int($0) } ?? (limit > 0 ? Int(used / limit * 100) : 0)
        let currency = extra.currency ?? "USD"
        // Same threshold ladder as the menu bar / popover. Extra Credits has
        // no reset window, so it never uses Smart Color; the static gauge
        // thresholds keep every surface in agreement.
        let tint = RiskZone.forPercent(pct, thresholds: settingsStore.thresholds).color

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                Text(String(localized: "dashboard.extra.title"))
                    .font(DS.Typography.title2)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(pct)%")
                    .font(.system(size: 20, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            if limit > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Pastel.track)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(tint)
                            .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100)
                    }
                }
                .frame(height: 6)
                HStack(spacing: DS.Spacing.xs) {
                    Text(CurrencyFormatter.formatMinorUnits(used, currencyCode: currency, locale: Locale(identifier: "en_US")))
                        .font(DS.Typography.label)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "dashboard.extra.separator"))
                        .font(DS.Typography.label)
                        .foregroundStyle(.tertiary)
                    Text(CurrencyFormatter.formatMinorUnits(limit, currencyCode: currency, locale: Locale(identifier: "en_US")))
                        .font(DS.Typography.label)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(localized: "dashboard.extra.monthly"))
                        .font(DS.Typography.label)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(String(localized: "dashboard.extra.noLimit"))
                    .font(DS.Typography.label)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Pastel.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Pastel.border, lineWidth: 1)
        )
    }

    // MARK: - Footer pills

    private var footerPills: some View {
        HStack(spacing: DS.Spacing.xs) {
            if let tier = usageStore.rateLimitTier {
                statusPill(icon: "sparkles", label: String(localized: "dashboard.tier"), value: tier.formattedRateLimitTier, tint: DS.Pastel.green)
            }
            if let org = usageStore.organizationName {
                statusPill(icon: "building.2.fill", label: String(localized: "dashboard.org"), value: org, tint: DS.Pastel.blue)
            }
            Spacer()
        }
    }

    private func statusPill(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(DS.Typography.micro)
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(DS.Typography.label)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .fill(DS.Pastel.card)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(tint.opacity(0.3), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Helpers

    /// Smart-aware gauge color helper. When the user enabled Smart Color,
    /// uses the risk-aware formula (utilization x time-to-reset); otherwise
    /// falls back to the static threshold ramp.
    private func gaugeColor(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> Color {
        GaugeColorResolver.color(
            mode: GaugeColorResolver.mode(smartColorEnabled: settingsStore.smartColorEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: settingsStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile
        )
    }

    private func gaugeGradient(pct: Int, resetDate: Date?, windowDuration: TimeInterval) -> LinearGradient {
        GaugeColorResolver.gradient(
            mode: GaugeColorResolver.mode(smartColorEnabled: settingsStore.smartColorEnabled, windowDuration: windowDuration),
            utilization: pct,
            resetDate: resetDate,
            windowDuration: windowDuration,
            thresholds: settingsStore.thresholds,
            pacingMargin: Double(settingsStore.pacingMargin),
            profile: settingsStore.smartColorProfile,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func zoneGlyph(for zone: PacingZone?) -> String {
        switch zone {
        case .chill:   "leaf.fill"
        case .onTrack: "bolt.fill"
        case .warning: "hare.fill"
        case .hot:     "flame.fill"
        case nil:      "sparkles"
        }
    }

    private func zoneLabel(_ zone: PacingZone) -> String {
        switch zone {
        case .chill:   String(localized: "pacing.zone.chill")
        case .onTrack: String(localized: "pacing.zone.ontrack")
        case .warning: String(localized: "pacing.zone.warning")
        case .hot:     String(localized: "pacing.zone.hot")
        }
    }

    private func refreshLastUpdateText() {
        if let date = usageStore.lastUpdate {
            lastUpdateText = date.formatted(.relative(presentation: .named))
        }
    }
}
