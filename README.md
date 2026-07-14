<p align="center">
  <img src="TokenEaterApp/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="RaiUsage">
</p>

<h1 align="center">RaiUsage</h1>

<p align="center">
  <strong>Monitor your Claude AI usage limits directly from your macOS desktop.</strong>
  <br>
  <a href="#install">Install</a> · A fork of <a href="https://github.com/AThevon/TokenEater">TokenEater</a> — cleaned up, simplified, unified UI
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/Claude-Pro%20%2F%20Max%20%2F%20Team-D97706" alt="Claude Pro / Max / Team">
</p>

---

> **Requires a Claude Pro, Max, or Team plan.** The free plan does not expose usage data.

## What is RaiUsage?

A native macOS menu bar app with a dashboard window and a quick-glance popover that tracks your Claude AI usage in real-time. Pastel, minimal, native.

RaiUsage is based on [TokenEater](https://github.com/AThevon/TokenEater) — cleaned up (widgets, overlay, updater, and theme engine removed), simplified to a focused menu-bar app, and given one unified pastel UI across every surface. See [Origin](#origin).

- **Menu bar** — Live percentages with color-coded thresholds. A fully configurable status item: pin any metrics, choose prefix/value/countdown per pin, pick all-pins / highest-risk / rotate display, and monochrome or risk colors.
- **Popover** — A single quick-glance popover with the metrics, pacing chips, and extra-credits spend you choose to show; reorderable.
- **Dashboard** — Sidebar window with Monitoring / History / Settings. Monitoring shows a hero session tile plus a grid of metric tiles that inline-expand to 7d sparklines, peak day, and a pacing-vs-equilibrium graph.
- **History** — Tokens-over-time browser sourced from Claude Code's local JSONL logs. Filter by model family, switch range (24h / 7d / 30d / 90d), hover bars for daily breakdown, identify your heaviest day and top project at a glance.
- **Smart Color** — Risk-aware coloring that combines absolute usage, projection rate, and pacing into a continuous risk score with early-window confidence damping. Three temperaments (Patient / Balanced / Vigilant) to dial sensitivity to your appetite for risk.
- **Smart pacing** — Are you burning through tokens or cruising? Four zones: chill, on track, warning, hot. Optional workweek pacing counts only your active days.
- **Notifications** — Granular per-surface (5h / 7d / Sonnet / Design) and per-event toggles (escalation, recovery, pacing, scheduled reset reminders, extra credits, token expiry, service status).

## Install

### Download DMG (no Xcode needed)

Grab the latest `RaiUsage-vX.Y.Z.dmg` from [Releases](https://github.com/RoodsBurger/ClaudeUsage/releases/latest), open it, and drag RaiUsage to Applications.

The DMG is ad-hoc signed and **not notarized** (no paid Apple Developer account), so on first launch Gatekeeper blocks it: **right-click the app > Open**, then confirm — or **System Settings > Privacy & Security > Open Anyway**. Once only.

### Build from source

**Requirements:** macOS 14+, [Xcode](https://apps.apple.com/app/xcode/id497799835) (App Store, opened once), and [Homebrew](https://brew.sh).

```bash
git clone https://github.com/RoodsBurger/ClaudeUsage.git
cd ClaudeUsage
./build.sh
```

The script installs [XcodeGen](https://github.com/yonaskolb/XcodeGen) if missing, builds Release, copies the app to `/Applications`, and launches it. Built on your own machine it opens directly — if Gatekeeper ever objects, right-click > **Open** once.

### First Setup

Requires a **Pro, Max, or Team plan**.

1. Open RaiUsage — the single-screen onboarding walks you through connecting
2. Choose **Sign in with Claude** (an app-owned OAuth login that refreshes on its own), or **Use Claude Code's session** to borrow the token Claude Code already has on this Mac

## Update

DMG installs: download the newer DMG from [Releases](https://github.com/RoodsBurger/ClaudeUsage/releases/latest) and replace the app. From source:

```bash
cd ClaudeUsage
git pull
./build.sh
```

Settings and the connection are preserved across updates.

## Uninstall

Delete `RaiUsage.app` from Applications, then optionally clean up shared data:
```bash
rm -rf /Applications/RaiUsage.app
rm -rf ~/Library/Application\ Support/com.raiusage.shared
```

## Build from source (manual)

What `./build.sh` runs under the hood:

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterApp \
  -configuration Release -derivedDataPath build build
cp -R "build/Build/Products/Release/RaiUsage.app" /Applications/
```

## Architecture

```
TokenEaterApp/           App host (settings, OAuth, menu bar, popover, dashboard)
Shared/                  Shared code (services, stores, models, pacing)
  ├── Models/            Pure Codable structs
  ├── Services/          Protocol-based I/O (API, TokenProvider, OAuth, SharedFile, Notification, SessionHistory)
  ├── Repositories/      Orchestration (UsageRepository)
  ├── Stores/            ObservableObject state containers (Usage, Settings, History, MonitoringInsights, VendorStatus)
  └── Helpers/           Pure functions (PacingCalculator, MenuBarRenderer, SmartColor)
```

The app signs in via its own OAuth login or borrows Claude Code's token silently from the macOS Keychain (`kSecUseAuthenticationUISkip`), calls the Anthropic usage API, and writes results to a shared JSON file. A `TokenFileMonitor` watches the credential files with a `DispatchSource` filesystem watcher and triggers an immediate refresh.

## How it works

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token>
anthropic-beta: oauth-2025-04-20
```

Returns `utilization` (0–100) and `resets_at` for each limit bucket.

## Security & Privacy

RaiUsage authenticates with an **OAuth access token** — either its own "Sign in with Claude" login (stored in an app-owned keychain item it creates, so no ACL prompt) or, if you choose to borrow it, the same standard token Claude Code itself uses. When borrowing, macOS prompts you once to allow reading that keychain item; this is normal macOS behavior for any app reading a keychain item it didn't create.

**What the app does with the token:**
- Calls `GET /api/oauth/usage` (your current usage stats)
- Calls `GET /api/oauth/profile` (your plan info)

**What the app cannot do:** send messages, read conversations, modify your account, or access anything beyond read-only usage data.

The token never leaves your machine except for these two API calls to `api.anthropic.com`. It lives only in the Keychain and memory, never on disk; the shared JSON file holds usage numbers only.

The entire codebase is open source and auditable: token resolution is in [`TokenProvider.swift`](Shared/Services/TokenProvider.swift) and [`SecurityCLIReader.swift`](Shared/Services/SecurityCLIReader.swift), the OAuth login in [`OAuthService.swift`](Shared/Services/OAuthService.swift), API calls in [`APIClient.swift`](Shared/Services/APIClient.swift).

## Troubleshooting

### Common issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Rate limited" or "API unavailable" | Your OAuth token has hit its per-token request limit | Run `claude /login` in your terminal for a fresh token - RaiUsage detects the change and recovers automatically within seconds |
| Keychain popup asking to access "Claude Code-credentials" | First run on a new install needs to authorize `/usr/bin/security` to read your Claude Code token | Click **Always Allow** once - it sticks across future app updates |

### Clean reset

If something is broken and you want to start fresh, run this in your terminal. It kills all related processes, wipes caches, preferences, and containers, then removes the app:

```bash
# 1. Kill processes
killall RaiUsage NotificationCenter cfprefsd 2>/dev/null; sleep 1

# 2. Wipe preferences
defaults delete com.raiusage.app 2>/dev/null
rm -f ~/Library/Preferences/com.raiusage.app.plist

# 3. Wipe sandbox containers
for c in com.raiusage.app; do
    d="$HOME/Library/Containers/$c/Data"
    [ -d "$d" ] && rm -rf "$d/Library/Preferences/"* "$d/Library/Caches/"* "$d/Library/Application Support/"* "$d/tmp/"* 2>/dev/null
done

# 4. Wipe shared data and caches
rm -rf ~/Library/Application\ Support/com.raiusage.shared
rm -rf ~/Library/Caches/com.raiusage.app

# 5. Remove the app
rm -rf /Applications/RaiUsage.app
```

> Some `Operation not permitted` errors on container metadata files are normal - macOS protects those, but the actual data is cleaned.

After this, reinstall with `./build.sh` (see [Install](#install)).

## Contributing

Contributions are welcome! Bug reports, feature ideas and code PRs all help. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the full guide - it covers the workflow, commit conventions, testing, and a few SwiftUI rules worth knowing before touching the code.

## Origin

RaiUsage is a fork of [TokenEater](https://github.com/AThevon/TokenEater) by AThevon — cleaned up, simplified, and given a unified pastel UI. The fork strips the widgets, floating overlay, in-app updater, and theme engine down to a focused menu-bar app; adds a native "Sign in with Claude" OAuth login with automatic refresh; and rebuilds every surface (menu bar, popover, dashboard, settings, onboarding) on one minimal design system. Credit for the original concept and foundation goes to the upstream project.

