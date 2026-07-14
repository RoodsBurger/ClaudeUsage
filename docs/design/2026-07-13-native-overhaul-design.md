# TokenEater Native Overhaul — Design Spec

Date: 2026-07-13
Status: approved by owner (fork intent, cut list, design language, spend design)

## Context

This repo is a personal fork of AThevon/TokenEater (v5.8.0), free to diverge from
upstream. The owner runs the app on two machines: a personal Mac (Claude Pro/Max
account) and a work Mac (Claude Enterprise account). Three problems drive this
overhaul:

1. **Enterprise mislabel.** Enterprise usage arrives via the API's `extra_usage`
   object, and the app labels it "Extra Credits" with a bare percentage. For an
   enterprise account that label is wrong, and the dollar figures the API provides
   (`used_credits`, `monthly_limit` in minor units + `currency`) are shown only on
   one dashboard tile — never in the menu bar, popover, or anywhere prominent.
2. **Visual identity sprawl.** Three design systems coexist (window `DS` tokens,
   theme-engine-colored popover/menu bar/overlay, separate widget tokens). The
   target look is the RaiDrive project's native macOS restraint.
3. **Unused surface area.** Widgets, the Agent Watchers overlay, the theme engine,
   the in-app updater/brew pipeline, legacy migrations, and French localization are
   unused by the owner.

## Goals

- One native macOS design language across every surface.
- Menu bar item as the primary surface: deeply configurable content, format,
  and display modes.
- Correct, plan-aware labeling of usage-based spend, with dollar amounts primary.
- Easy install on the work machine: downloadable DMG from GitHub Releases.
- Self-sufficient auth: sign in once per machine, app keeps itself authenticated
  — no Claude Code terminal required, no re-auth after reboot.
- Same binary adapts to personal (Pro/Max) and work (Enterprise) accounts with no
  mode switch — everything derives from the API response.
- A raw API response viewer so unknown account shapes can be inspected in-app.
- Substantially smaller codebase: delete unused features and legacy code.

## Non-goals

- No upstream compatibility; no PRs back to the original repo.
- No rename: app name, bundle IDs (`com.tokeneater.app`), and shared-cache paths
  stay, because renaming breaks Keychain ACL trust and signing. Cosmetic rename may
  happen later.
- No new metrics beyond what the two existing endpoints return.

## 1. The cut

Deleted outright (code, tests, project targets, docs references, CI steps):

| Area | Items |
|---|---|
| Widgets | `TokenEaterWidget/` target, widget entitlements, `NSExtension` plutil hack in workflows/docs, widget nuke instructions, `WidgetReloader` helper |
| Overlay / Agent Watchers | `OverlayWindowController`, `OverlayView`, `AgentWatchersSectionView`, `SessionMonitorService`, `SessionStore`, `OverlayHitTest`, `OverlayTriggerZone`, `WatcherStyle`, `WatcherVisibility`, `WatcherScanInterval`, `WatcherDisplayMode`, overlay settings store/UI |
| Theme engine | `ThemeStore`, `ThemeModels`, `ThemesSectionView`, theme presets, `SmartColorProfile` presets, `GlowText`, `AnimatedGradient` |
| Updater / distribution | `UpdateService`, `UpdateStore`, `SignatureVerifier`, `BrewMigrationService`, `UpdateModalView`, `SparklePublicKey.txt`, `installer.applescript`, `docs/appcast.xml`, release + homebrew CI workflows, `UpdateModels` |
| Legacy migrations | `LegacyHelperCleanupService`, `SharedFileService` old-product-name + group-container migrations, `ElectronDecryptionService` keychain→file shim, `AppSection` legacy alias parsing, `DisplaySettingsStore` legacy-default migrations, `ThemeColors` legacy `SmartLevel` mapping, pre-`pacingWarning` theme decoder |
| Localization | `Shared/fr.lproj` (English only) |
| Popover | 2 of 3 layout variants; a single layout survives (section 3) |

Deleted tests go with their code (widget, overlay, theme, update, migration suites).

Kept fully working:

- Token resolution stack: `TokenProvider` with all 4 sources (`SecurityCLIReader`,
  `CredentialsFileReader`, `ClaudeConfigReader` + `ElectronDecryptionService`,
  direct Keychain fallback), `TokenFileMonitor`, silent-read rule.
- `APIClient` (both endpoints, SOCKS proxy support), `UsageRepository`.
- `UsageStore`, `SettingsStore`, pacing (`PacingCalculator`, bars, projections),
  notifications (`NotificationService`, thresholds), History (JSONL parsing via
  `SessionHistoryService`/`JSONLParser`, `HistoryStore`), Monitoring window,
  onboarding (simplified, section 3), vendor status banner, diagnostics.
- `ci.yml` build + test workflow; `build.sh`; the test suite for kept code.

`SharedFileService` shrinks to a plain offline-cache writer/reader (last-known
`CachedUsage` snapshot in `~/Library/Application Support/com.tokeneater.shared/`)
— no widget consumer remains, but the offline snapshot keeps launch instant.

`ProcessResolver` survives only for `detectClaudeCodeVersion()` (User-Agent
header); its session-scanning half goes with the overlay.

## 2. Design system

> **REVISED 2026-07-13 (owner design review):** the original "system colors only,
> no hex" rule is superseded. The owner wants a specific **pastel palette** and a
> **solid, opaque, dark** look (RaiDrive-like, not translucent). Hex is now allowed
> **only** in the one `DS` palette definition; every view still references `DS`
> tokens / `RiskZone` / `PacingZone`, never raw hex. The app is **dark-first**
> (fixed dark panels); only the **menu bar** adapts to the wallpaper.

### Pastel palette (single source of truth in `DS`)

| Token | Pastel (dark bg) | Deepened (light bg, menu-bar only) |
|---|---|---|
| risk OK (green) | `#86D6A0` | `#4FAE74` |
| risk warning (amber) | `#F2C288` | `#D99A4E` |
| risk critical (coral) | `#EF9A8D` | `#D46A58` |
| info / on-track (blue) | `#93B4EE` | `#5B82D6` |

Surfaces: **app windows** are opaque solid dark (no wash-out) — window base
`#161719`, card/elevated `#1A1B1E`, hairline `#2C2E33`, gauge track `#26282D`.
The **popover** is the exception: it keeps the **native macOS translucent window
material** (RaiDrive-style vibrancy), not a solid fill — its cards/tracks still
use the tokens above for contrast over the material. No glow anywhere. Text
keeps SwiftUI `.primary` / `.secondary` / `.tertiary` (resolve white-ish on the
dark surfaces). `RiskZone.color`/`.nsColor` and `PacingZone.semanticColor` return
these pastels (chill→green, onTrack→blue, warning→amber, hot→coral).

### Menu bar rendering — option B (adaptive text + colored dot)

The status-item text must stay legible over any wallpaper. Rendering:
- **Text** uses the menu bar's effective appearance: near-white (`#F4F4F6`) on a
  dark menu bar, near-black (`#1C1C1E`) on a light one. `MenuBarRenderer.RenderData`
  gains `menuBarIsDark: Bool`; `StatusBarController` reads
  `statusItem.button.effectiveAppearance` and re-renders on appearance change.
- **Risk color** rides a small filled dot before each metric (pastel on a dark
  bar, the deepened variant on a light bar). `colorMode = .risk` shows dots;
  `colorMode = .monochrome` shows none (adaptive text only).

Everything below still holds (SF Symbols hierarchical, `.rounded` only for the app
name + hero numbers, `.monospacedDigit()` on all numerics, 14pt inset, `Divider()`
separation in the popover, `RoundedRectangle` cards) — recolored to the palette
above and made opaque.

- **Color by role, never by theme.** Risk drives color: ok = `.green`, warning =
  `.orange`, critical = `.red`, active/info = `.blue`. Text hierarchy `.primary` /
  `.secondary` / `.tertiary`. Tinted fills are the same semantic color at
  `opacity(0.10–0.15)`. Accent = system accent (empty AccentColor asset).
  `SmartColor`'s risk model survives but maps to these semantic colors.
- **Typography.** `.rounded` design reserved for the app name and hero numbers
  (`.font(.system(.headline, design: .rounded))` pattern). Everything else uses
  semantic Dynamic Type sizes: section headers `.subheadline.weight(.semibold)`,
  row text `.caption`, metadata `.caption2`. Every numeric value gets
  `.monospacedDigit()`.
- **Structure.** 14pt horizontal inset everywhere; vertical rhythm 10/8/6/4;
  `Divider()` separation instead of cards in the popover. Dashboard tiles are
  quiet `RoundedRectangle` with `.quinary`-level fills — no shadows, gradients, or
  glow anywhere.
- **Icons.** SF Symbols with `.symbolRenderingMode(.hierarchical)`; tinted-circle
  icon containers (32pt standard, 72pt hero); `symbolEffect(.pulse)` on the status
  glyph while a refresh is in flight.
- **Controls.** `.borderedProminent` for the one primary CTA per screen,
  `.borderless` for toolbars, `Button(role: .destructive)` for destructive rows,
  `.formStyle(.grouped)` + `LabeledContent` for settings.

## 3. Surfaces

- **Menu bar item — the primary surface.** The owner lives in the menu bar, so
  it gets the deepest configurability. `MenuBarRenderer` stays a pure, unit-
  tested helper; AppKit `NSStatusItem` hosting is unchanged. Everything below is
  user-configurable from a new Settings → Menu Bar section with a live preview:
  - **Pinned metrics.** Any subset of available metrics (session 5h, weekly,
    per-model weeklies, spend), user-ordered, shown side by side with a
    configurable separator (`·` default).
  - **Per-metric format.** Prefix style (SF Symbol, short label like `5h`/`W`,
    or none) and value style (percent, dollars for spend, remaining instead of
    used) per pinned metric.
  - **Display modes.** All-pinned row · highest-risk-only (single metric, the
    one closest to its limit) · rotate through pinned metrics every N seconds.
  - **Reset countdown.** Optional inline countdown next to a metric
    (`42% · 2h13m`), format configurable (compact / clock time).
  - **Color.** Monochrome template (native menu bar look) or semantic risk
    coloring (green/orange/red); applies to text, icon, or both.
  - **Icon.** Show/hide the app glyph; glyph tint follows overall risk;
    `symbolEffect(.pulse)` during refresh.
  - All numbers `.monospacedDigit()` to prevent menu bar width jitter; fixed-
    width rendering option to stop neighbor icons shifting.
- **Popover (single layout, ~340pt wide).** Vertical stack with dividers:
  1. Header: 32pt tinted status disc (pulsing hierarchical symbol) + app name in
     `.rounded` + plan badge + account email `.caption .tertiary`.
  2. Vendor outage banner (orange-tint inline pattern) when active.
  3. Metric rows — one per bucket present in the response (session 5h, weekly
     all-model, per-model weekly): label, thin native gauge, `%` monospaced,
     reset countdown in `.tertiary`.
  4. Spend section (when `extra_usage` present): plan-aware label, `$used / $limit`
     primary, thin bar + percent secondary.
  5. Footer toolbar: refresh · open dashboard · settings · quit — borderless,
     11pt symbols, 20pt hit targets.
- **Main window.** Native toolbar + sidebar navigation: Monitoring / History /
  Settings. Monitoring keeps the tile grid and hero pacing graph, flattened to
  semantic colors and `DS` tiles. History view keeps its charts, recolored.
  Settings sections rebuilt as grouped forms (`.formStyle(.grouped)`), replacing
  the custom "dark premium" chrome; remaining sections: General (refresh
  interval, menu bar style, pinned metrics, proxy), Pacing, Notifications,
  Diagnostics.
- **Onboarding.** Single hero screen replacing the card deck: 72pt tinted circle
  + light hierarchical glyph, `.rounded` title, one-line explanation, one
  `.borderedProminent` Connect button that calls `TokenProvider.bootstrap()`
  (the only interactive Keychain read). Error and retry states inline.

## 4. Spend & enterprise behavior

- **Model.** `ExtraUsage` is renamed conceptually to the spend metric (type name
  `SpendInfo`, decoded from `extra_usage`; JSON keys unchanged). Fields used:
  `is_enabled`, `used_credits`, `monthly_limit` (minor units), `currency`,
  `utilization`, `disabled_reason`.
- **Plan-aware label.** From `/api/oauth/profile`:
  `organization.organization_type == "claude_enterprise"` or `"claude_team"` →
  label **"Organization usage"**; otherwise → **"Extra usage"**. `PlanType`
  detection logic is unchanged; the label mapping is new.
- **Dollars primary.** `$used / $limit` rendered by `CurrencyFormatter` from minor
  units, honoring `currency`. Percent + bar are secondary. When `monthly_limit`
  is absent or 0: show `$used` with a "no cap" caption instead of a fake 0%.
  Menu bar pin shows `$used` compact (e.g. `$142`).
- **`billing_type` used.** Shown as a pill in the dashboard header next to
  rate-limit tier and org name.
- **Resilient decoding.** Sections render only if their bucket is present
  (existing behavior, preserved). The decoder additionally retains the raw
  response `Data` so unknown fields are inspectable rather than silently dropped.
- **Raw API viewer.** Settings → Diagnostics → "API Response": on demand, fetch
  both endpoints, pretty-print the JSON with the bearer token never included
  (it is a request header, not response content — viewer renders response bodies
  only), plus a Copy button. Purpose: at work, the owner opens the viewer once
  and we learn the exact enterprise response shape; any follow-up label/parsing
  adjustment becomes trivial.
- **No mode switch.** Personal Mac shows Pro/Max buckets; work Mac shows
  enterprise labeling + dollars. All differences derive from response + profile.

## 5. Self-sufficient authentication

Today the app only borrows Claude Code's OAuth token (Keychain item
`Claude Code-credentials` via the `security` CLI, or credential files) and has
no refresh capability of its own. Two failure modes follow:

- The borrowed access token expires unless Claude Code itself is running to
  refresh it — hence "keep a terminal open".
- Local ad-hoc builds change code-signing identity, so the Keychain ACL
  "Always Allow" doesn't stick and every reboot/rebuild re-prompts.

Fix:

- **First-class OAuth login (primary).** New `OAuthService` implementing the
  same authorization-code + PKCE flow Claude Code uses (public client id,
  `claude.ai` authorize page, token exchange endpoint). Login: browser opens →
  user authorizes → local loopback callback (127.0.0.1, random port; manual
  code-paste fallback) → access + refresh tokens stored in an **app-owned**
  Keychain item (service `com.tokeneater.oauth`). Because the app creates the
  item, reads are ACL-prompt-free regardless of signing identity.
- **Autonomous refresh.** `TokenProvider` refreshes proactively before
  `expiresAt` and reactively on 401 (refresh → retry once). No dependency on
  Claude Code running; survives reboots for the refresh token's lifetime.
- **Borrowed token demoted to fallback.** The existing Claude Code readers
  remain as a secondary "use Claude Code's session" connect option (useful
  first-run shortcut), clearly labeled, with its known limitations.
- **Onboarding:** primary button "Sign in with Claude" (runs OAuthService),
  secondary "Use Claude Code's token" (runs today's bootstrap).
- **Sign out:** deletes the app-owned Keychain item and clears in-memory cache.
- Tokens live only in the Keychain and memory — never on disk; `shared.json`
  continues to hold usage numbers only.
- **Risk:** the OAuth client id/endpoints are unpublished internals and could
  change; the borrowed-token fallback stays as the safety net. Validated by a
  real login during implementation.

## 6. Project & CI changes

- `project.yml`: drop the widget target and its entitlements/plist wiring; keep
  `TokenEaterApp` and `TokenEaterTests`; remove the installer prebuild step.
  Regenerate with `xcodegen generate`.
- Workflows: keep `ci.yml` (build + tests on PR/push). Replace `release.yml`
  with a trimmed release workflow: on `v*` tag (or manual dispatch), build
  Release, ad-hoc sign, package a DMG, attach it to a GitHub Release. No
  notarization (owner has no paid Apple Developer account); Sparkle/appcast/
  homebrew publishing deleted. Delete `test-build.yml`.
- **Install story (work machine).** Download DMG from the fork's GitHub
  Releases → drag to /Applications → first launch via right-click → Open (or
  System Settings → Privacy & Security → Open Anyway) because the build is not
  notarized. Documented as a short "Install" section in the README. Known risk:
  a strict MDM policy that fully blocks unidentified developers would require
  building from source on the work machine instead; treated as a fallback, not
  the primary path.
- Docs (`README`/`SETUP`/`AGENTS`): rewrite to match the reduced app after
  implementation stabilizes.

## 7. Staging & verification

Four stages, each ending with a green build + tests:

1. **Strip.** Delete cut-list items, fix compilation, prune project.yml and CI,
   delete orphaned tests. App runs with old look minus removed features.
2. **Reskin.** New `DS`, single popover, semantic colors, grouped settings,
   sidebar main window, hero onboarding, menu bar configurability (pinned
   metrics, formats, display modes, live preview).
3. **Auth.** `OAuthService` + autonomous refresh + onboarding sign-in +
   sign-out; borrowed-token readers demoted to fallback.
4. **Spend + ship.** `SpendInfo` + plan-aware labels + dollar displays + menu
   bar `$` pin + raw API viewer + `billing_type` pill + enterprise-shaped JSON
   fixtures; trimmed DMG release workflow + README install section.

Verification per repo rules:

- Full test suite after each stage (`xcodebuild ... -scheme TokenEaterTests test`).
- Release-configuration build with the Xcode 16.4 toolchain for any SwiftUI
  change; manual popover/menu-bar/dashboard walkthrough.
- Hard SwiftUI rules remain law: no `@Observable`, no `@StateObject` in the App
  struct, no bindings to computed properties, silent token reads.
- Enterprise behavior unit-tested with fixture JSONs (enterprise-shaped
  `extra_usage` + `claude_enterprise` profile); real-world confirmation via the
  raw API viewer on the work machine.

## Risks

- **Enterprise response shape is unvalidated.** We have never seen a real
  enterprise payload; the design assumes `extra_usage` carries the spend. The raw
  API viewer is the mitigation — worst case, labels/parsing adjust after one
  viewer screenshot.
- **Release-only SwiftUI bugs.** The reskin touches every view; the Release-build
  + manual-test discipline is the mitigation.
- **Deleting the widget target** touches project.yml, entitlements, CI, and docs
  simultaneously; stage 1 is kept mechanical (delete + compile) to contain this.
