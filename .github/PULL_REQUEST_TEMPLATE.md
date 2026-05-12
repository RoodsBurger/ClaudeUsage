<!--
Thanks for opening a PR! A few things to make review smooth:
- Link the issue this fixes/closes (e.g. `Closes #123`). If there's no issue and the change is non-trivial, please open one first.
- Keep the PR focused on a single concern.
- Fill the checklist before requesting review.
-->

## What this PR does

<!-- One or two sentences describing the change. -->

## Why

<!-- The motivation. Link the related issue if there is one. -->

Closes #

## How to test

<!-- Steps a reviewer can follow to verify the change locally. Be specific. -->

1.
2.
3.

## Screenshots / recordings (if UI-related)

<!-- Drag images or videos here, or delete this section. -->

## Checklist

- [ ] Branch is rebased on the latest `main`
- [ ] Code builds cleanly in Release with Xcode 16.4
- [ ] Unit tests pass locally (`xcodebuild ... -scheme TokenEaterTests test`)
- [ ] If SwiftUI was touched: tested manually in Release (not just Debug)
- [ ] If widget was touched: tested manually after a full cache nuke
- [ ] Followed the SwiftUI rules in `CLAUDE.md` (no `@Observable`, no `@StateObject` in App struct, no bindings to computed properties, etc.)
- [ ] Commits follow Conventional Commits (`feat:`, `fix:`, `chore:`, etc.)
- [ ] No new compiler warnings
- [ ] Updated docs (`README.md`, `SETUP.md`, `CLAUDE.md`) if behavior or setup changed

## Additional notes for reviewer

<!-- Anything else worth flagging - tradeoffs, follow-up work, things you'd like specific feedback on. Delete if not needed. -->
