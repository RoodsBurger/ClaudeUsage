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

## Build

```bash
git clone https://github.com/AThevon/TokenEater.git
cd TokenEater

# Install XcodeGen
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Build
xcodebuild -project TokenEater.xcodeproj \
  -scheme TokenEaterApp \
  -configuration Release \
  -derivedDataPath build build
```

### Install

```bash
cp -R "build/Build/Products/Release/RaiUsage.app" /Applications/
```

> **Note** - this section covers building from source for local development. The build above is signed with your Apple Development cert (or ad-hoc) and is **not notarized**, so Gatekeeper will block the first launch:
>
> 1. Double-click **RaiUsage.app** in Applications - macOS will block it
> 2. Open **System Settings -> Privacy & Security** -> scroll to the RaiUsage entry -> click **Open Anyway**
>
> If you want a frictionless install, **download the official notarized DMG from [Releases](https://github.com/AThevon/TokenEater/releases/latest)** instead - it opens directly without any Gatekeeper prompt.

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
| App flagged as malware | You're running an ad-hoc local build that stripped its quarantine attrs. Either reinstall via the official notarized DMG from [Releases](https://github.com/AThevon/TokenEater/releases/latest), or rebuild + approve via System Settings -> Privacy & Security -> Open Anyway |
