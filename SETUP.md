# RaiUsage — Setup

Native macOS menu bar app to display Claude usage (session, weekly all models, weekly Sonnet, and more), with a dashboard window and a quick-glance popover.

## Prerequisites

1. **macOS 14 (Sonoma)** or later
2. **Xcode 15+** installed from the Mac App Store (Xcode 16.4 recommended for validating SwiftUI/Release changes, see [`AGENTS.md`](AGENTS.md) for why)
3. **Homebrew** (for XcodeGen)
4. **Claude Code** installed and authenticated (`claude` then `/login`)

### Install Xcode

```bash
# After installing Xcode.app:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## Build & Install (one script)

```bash
git clone https://github.com/RoodsBurger/RaiUsage.git
cd RaiUsage
./build.sh
```

`build.sh` installs XcodeGen if missing, generates the Xcode project, builds Release, copies the app to `/Applications`, and launches it.

### Manual steps (what the script does)

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project TokenEater.xcodeproj \
  -scheme TokenEaterApp \
  -configuration Release \
  -derivedDataPath build build
cp -R "build/Build/Products/Release/RaiUsage.app" /Applications/
```

> **Note** - local builds are ad-hoc signed and **not notarized**. Built on your own machine they carry no quarantine flag and open directly. If Gatekeeper ever blocks the launch:
>
> 1. Right-click **RaiUsage.app** in Applications > **Open**, or
> 2. **System Settings -> Privacy & Security** -> scroll to the RaiUsage entry -> click **Open Anyway**

## Configuration

1. Open **RaiUsage.app** — the single-screen onboarding guides you through setup
2. Choose **Sign in with Claude** (app-owned OAuth login) or **Use Claude Code's session** to borrow the token Claude Code already holds on this Mac

## Structure

```
TokenEaterApp/               App host (menu bar, popover, dashboard, onboarding)
  ├── App/                      # @main + AppDelegate + StatusBarController, store wiring
  ├── Windows/                  # Dashboard window (Monitoring / History sections)
  ├── Popover/                  # Menu bar quick-glance popover
  ├── Settings/                 # Grouped settings sections
  ├── Onboarding/               # Single-screen hero onboarding + OAuth view model
  └── TokenEaterApp.entitlements
Shared/                      Shared code (compiled into both targets)
  ├── Models/                Pure Codable structs
  ├── Services/              Protocol-based I/O (+ Protocols/)
  ├── Repositories/          UsageRepository (API -> shared file)
  ├── Stores/                ObservableObject state containers
  ├── Helpers/               Pure functions
  ├── Components/             Reusable SwiftUI views
  ├── Design/                Design tokens
  └── en.lproj               Localization (EN)
```

## API

- **Endpoint**: `GET https://api.anthropic.com/api/oauth/usage`
- **Auth**: `Authorization: Bearer <oauth-token>`
- **Response**:
  - `five_hour.utilization` — Session (5h sliding window)
  - `seven_day.utilization` — Weekly all models
  - `seven_day_sonnet.utilization` — Weekly Sonnet only

The OAuth token is managed by Claude Code and refreshes automatically.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Menu bar shows an error | Reopen the app and check the connection in Settings |
| "Not connected" | Launch the app and complete onboarding (Sign in with Claude, or borrow Claude Code's session) |
| Build fails | Verify `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` points to Xcode.app |
| App flagged as malware | Ad-hoc local builds are not notarized. Approve via System Settings -> Privacy & Security -> Open Anyway, or rebuild with `./build.sh` (it clears the quarantine flag) |
