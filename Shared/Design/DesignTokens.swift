import SwiftUI
import AppKit

/// RaiUsage design tokens -> single source of truth for the window app chrome
/// (sidebar, cards, panels, typo, spacing, motion).
///
/// Scope : window app only. Does NOT apply to the menu bar or popover, which
/// keep their existing identity.
///
/// Cohabits with the semantic `RiskZone` / `PacingZone` colors (see
/// `Shared/Design/Semantic.swift`) which color *only* the data points
/// (gauges, pacing dots, metric values). The chrome stays constant
/// regardless of a data point's risk zone.
///
/// Reference -> `docs/design/MASTER.md`
enum DS {

    // MARK: - Palette (Chrome)

    enum Palette {
        // Faint hairline for popover sub-panel edges.
        static let glassBorderLo = Color.white.opacity(0.04)
    }

    // MARK: - Spacing

    /// Base 4pt, multiplicative scale. A card uses a single internal padding
    /// level (`.md` by default); sub-groups breathe with `.xs`/`.sm`.
    enum Spacing {
        static let xxs:  CGFloat = 4
        static let xs:   CGFloat = 8
        static let sm:   CGFloat = 12
        static let md:   CGFloat = 16
        static let lg:   CGFloat = 24
        static let xl:   CGFloat = 32
    }

    // MARK: - Radii

    /// Rule : larger surface -> larger radius. Tightened from the original
    /// soft-glass scale -> pulled values down to read more crisp / less
    /// "pill-y" without going full sharp-edged.
    enum Radius {
        static let input:  CGFloat = 6
        static let card:   CGFloat = 8
        static let cardLg: CGFloat = 12
    }

    // MARK: - Layout

    /// Hard-coded layout dimensions for top-level windows / panels.
    /// Centralised so the onboarding (and future panels) read from a single
    /// source instead of magic numbers in `MainAppView`.
    enum Layout {
        /// Onboarding window - compact, single-column hero screen (logo,
        /// title, caption, connect CTAs). The user passes through this once
        /// at first launch (and again if they reset onboarding from Settings).
        static let onboardingWindow = CGSize(width: 520, height: 560)

        /// Horizontal inset for a Settings section's header (title/subtitle/
        /// trailing action), matching the leading/trailing margin
        /// `.formStyle(.grouped)` gives its own Section content. Keeps every
        /// section's header aligned with the form below it instead of
        /// sitting flush against - or overflowing - the pane edge.
        static let settingsHeaderInset: CGFloat = 20
    }

    // MARK: - Native design constants (stage-2 language)

    /// Icon disc sizes for various contexts.
    enum IconDisc {
        static let standard: CGFloat = 32
        static let hero: CGFloat = 72
    }

    // MARK: - Motion

    enum Duration {
        static let base: Double = 0.24   // default transitions
    }

    enum Motion {
        static let easeInOut  = Animation.easeInOut(duration: Duration.base)
        static let springSnap = Animation.spring(response: 0.30, dampingFraction: 0.90) // hover / press
    }

    // MARK: - Typography

    /// Scale typographique. On s'appuie sur `.system` (SF Pro / SF Pro Display /
    /// SF Mono) pour zéro dépendance. Inter Display reste l'ambition long-terme
    /// mentionnée dans le MASTER.md -> on ship le font avec le bundle quand on
    /// veut le basculer, sans toucher aux call sites.
    enum Typography {
        static let title1       = Font.system(size: 22, weight: .semibold)
        static let title2       = Font.system(size: 17, weight: .semibold)
        static let body         = Font.system(size: 13, weight: .regular)
        static let label        = Font.system(size: 11, weight: .medium)
        static let micro        = Font.system(size: 10, weight: .medium)
        static let metricInline = Font.system(size: 13, weight: .regular, design: .monospaced)
    }
}

// MARK: - Pastel palette (2026-07-13 design revision)

/// The app's single palette: pastel risk colors on opaque dark surfaces.
/// Hex literals live ONLY here (and inside the `Color(hex:)`/`NSColor(hex:)`
/// inits in `Shared/Extensions/Extensions.swift`) - every other view or
/// helper references `DS.Pastel` / `RiskZone` / `PacingZone`, never a raw hex
/// value. See `docs/design/2026-07-13-native-overhaul-design.md` section 2.
extension DS {
    enum Pastel {
        // Risk zones - pastel, for use on the app's dark surfaces.
        static let green = Color(hex: 0x86D6A0)
        static let amber = Color(hex: 0xF2C288)
        static let coral = Color(hex: 0xEF9A8D)
        static let blue  = Color(hex: 0x93B4EE)

        // Deepened variants - contrast-boosted, for a LIGHT menu bar only.
        static let greenDeep = Color(hex: 0x4FAE74)
        static let amberDeep = Color(hex: 0xD99A4E)
        static let coralDeep = Color(hex: 0xD46A58)
        static let blueDeep  = Color(hex: 0x5B82D6)

        // Opaque surfaces - window/popover chrome, no material or vibrancy.
        static let base   = Color(hex: 0x161719) // window/popover background
        static let card   = Color(hex: 0x1A1B1E) // elevated card
        static let border = Color(hex: 0x2C2E33) // hairline
        static let track  = Color(hex: 0x3A3D45) // gauge/bar track - light enough to read as an empty bar on dark/translucent surfaces

        /// NSColor mirrors, needed wherever AppKit (not SwiftUI) draws -
        /// chiefly the menu bar's custom `NSAttributedString` rendering.
        enum NS {
            static let green = NSColor(hex: 0x86D6A0)
            static let amber = NSColor(hex: 0xF2C288)
            static let coral = NSColor(hex: 0xEF9A8D)
            static let blue  = NSColor(hex: 0x93B4EE)

            static let greenDeep = NSColor(hex: 0x4FAE74)
            static let amberDeep = NSColor(hex: 0xD99A4E)
            static let coralDeep = NSColor(hex: 0xD46A58)
            static let blueDeep  = NSColor(hex: 0x5B82D6)

            /// Adaptive menu bar text - near-white on a dark bar, near-black
            /// on a light one. The risk signal lives in the dot
            /// (`RiskZone.dotColor`/`PacingZone.dotColor`), not the text.
            static let textOnDark  = NSColor(hex: 0xF4F4F6)
            static let textOnLight = NSColor(hex: 0x1C1C1E)
        }
    }
}

