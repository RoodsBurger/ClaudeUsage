# Contributing to TokenEater

Hey! Thanks for considering a contribution. TokenEater started as a solo side project and I'm happy to see other people wanting to help. This document tells you how to do that without us stepping on each other's toes.

## Quick rules

- All issues, PRs, commits, branches and comments must be in **English**.
- Open an issue **before** writing code for a non-trivial change. Saves you from coding something I'd reject.
- If you're not sure whether something belongs in TokenEater, ask first. I'd rather say "great idea" than "sorry, scope creep".

## Reporting bugs

Use the **Bug report** issue template (it'll guide you). The more info you give me up front, the faster I can fix it. The non-negotiable infos:

- macOS version
- TokenEater version (see *Settings -> About* or the menu bar tooltip)
- Steps to reproduce (1, 2, 3 - clear and minimal)
- What you expected vs. what happened
- A screenshot or screen recording if it's UI-related
- Console logs if you have them (`Console.app`, filter by `TokenEater`)

If you can't reproduce reliably, say so. "Happens sometimes" is fine, just say it.

## Suggesting features

Use the **Feature request** issue template. Tell me:

- What you want to do (the user story, not the implementation)
- Why current behavior doesn't cover it
- What you've tried as a workaround

Don't start coding a feature without an issue first - I have a pretty strong opinion on TokenEater's scope and I'd hate for you to waste a weekend on something I won't merge.

## Contributing code

### 1. Prerequisites

Setup is in [`SETUP.md`](SETUP.md). TL;DR:

- macOS 14+
- Xcode 16.4 (exactly - newer versions can surface Swift 6.1 bugs that don't repro locally, see [`CLAUDE.md`](CLAUDE.md) for the gory details)
- `brew install xcodegen`

### 2. Fork and branch

1. Fork the repo on GitHub.
2. Clone your fork locally.
3. Create a branch off `main` with a descriptive name:

```
feat/agent-watchers-keyboard-shortcut
fix/popover-refresh-button-not-visible
chore/bump-sparkle-version
docs/clarify-keychain-prompt
```

Prefix conventions: `feat/`, `fix/`, `chore/`, `docs/`, `refactor/`, `test/`. Kebab-case after the prefix.

### 3. Code it

A few things worth knowing before you touch the code:

- **Architecture**: MV pattern + Repository pattern + protocol-oriented services. No singletons, dependencies are injected. Stores are `ObservableObject` + `@Published`, passed via `@EnvironmentObject`. See the *Architecture* section in [`README.md`](README.md) for the layout.
- **SwiftUI rules**: There are a few hard rules that have caused real production bugs - the most important ones:
  - **Do not use `@Observable`** (Swift 5.9 Observation framework). The whole codebase uses `ObservableObject` + `@Published`. There's a Release-only freeze bug under Swift 6.1.x that's invisible in Debug. Just don't.
  - **Do not put `@StateObject` in the `App` struct.** Use `private let store = Store()`.
  - **Do not create bindings to computed properties** or use `Binding(get:set:)`. They cause infinite re-evaluation loops.
  - Full list and rationale in [`CLAUDE.md`](CLAUDE.md) -> *SwiftUI rules section*. Read it once before submitting a PR that touches views.
- **Sandbox**: the widget extension is sandboxed (WidgetKit requires it). The main app is not. Anything that hits Keychain or the network must live in the main app, not the widget.

### 4. Test it

Run the unit tests (80+ tests covering stores, repository, pacing, token recovery):

```bash
xcodegen generate
xcodebuild -project TokenEater.xcodeproj -scheme TokenEaterTests \
  -configuration Debug -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO \
  test
```

**When to add tests**: anything you touch in `Shared/` (stores, services, repository, helpers, models). Tests use Swift Testing (`import Testing`, `@Test`, `#expect`). Mocks live in `TokenEaterTests/Mocks/`.

**When to test manually**: SwiftUI changes, widget rendering, anything visual. Build a Release version and install it locally - the *Build + Nuke + Install* one-liner in [`CLAUDE.md`](CLAUDE.md) does exactly that. Widget changes especially need a manual install because macOS aggressively caches widget extensions.

### 5. Commit

We use **[Conventional Commits](https://www.conventionalcommits.org/)**. Format:

```
<type>: <short imperative description>

<optional longer body explaining why>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `style`, `ci`.

Examples of good commits:

```
feat: add keyboard shortcut to toggle agent watchers
fix: refresh slider hidden under popover edge on macOS 14
chore: bump Sparkle to 2.6.4
docs: clarify keychain prompt behavior on first launch
```

Keep commits focused. A PR with one logical commit is great. A PR with 12 "wip" commits is not - squash before requesting review, or I'll squash on merge.

### 6. Open a PR

Push your branch to your fork, then open a PR against `main`. The PR template will ask you a few things - fill it in.

**PR checklist** (before requesting review):

- [ ] Branch is up to date with `main` (`git fetch origin && git rebase origin/main`)
- [ ] Code builds cleanly in Release with Xcode 16.4
- [ ] Unit tests pass locally
- [ ] If you changed SwiftUI: tested manually in Release (not just Debug - some bugs only appear in Release)
- [ ] If you changed the widget: tested manually after a full cache nuke (see `CLAUDE.md`)
- [ ] No new compiler warnings
- [ ] Commit messages follow Conventional Commits

CI will run the build and tests on your PR. Wait for it to go green before pinging me.

## Code style

There's no `swiftlint` config (yet), so just match the surrounding code. A few high-signal things:

- 4-space indentation, no tabs
- Trailing commas in multi-line collections where Swift allows them
- `// MARK: - Section` to organize long files
- Prefer `private` and `let` by default
- Don't write doc comments for trivial things, but do explain non-obvious *why* in comments

## Questions, help, ideas

- **General questions**: open a GitHub Discussion or an issue with the `question` label.
- **Found a security issue?** Don't open a public issue - email me directly at [adrien.thevon@pictarine.com](mailto:adrien.thevon@pictarine.com).

Thanks again for contributing. Even just opening a well-written bug report helps a lot.
