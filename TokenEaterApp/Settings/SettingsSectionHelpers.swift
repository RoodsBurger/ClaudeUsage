import SwiftUI

// MARK: - Settings header

/// Shared header for every Settings section: a restrained title (never bold/
/// heavy/rounded), an optional one-line `.secondary` subtitle, and an
/// optional trailing action control. Horizontally inset to
/// `DS.Layout.settingsHeaderInset` so it lines up with the grouped `Form`
/// content below instead of sitting flush against - or overflowing - the
/// pane edge. Used by all 5 settings sections (Menu Bar, Popover, General,
/// Pacing, Notifications) so the whole sidebar reads as one system.
@ViewBuilder
func settingsHeader<Action: View>(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder action: () -> Action
) -> some View {
    HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        Spacer(minLength: 12)
        action()
    }
    .padding(.horizontal, DS.Layout.settingsHeaderInset)
    .padding(.top, 12)
    .padding(.bottom, 4)
}

func settingsHeader(_ title: String, subtitle: String? = nil) -> some View {
    settingsHeader(title, subtitle: subtitle) { EmptyView() }
}

// MARK: - Click Chip

/// Generic click-to-toggle chip. Two visual styles:
/// - `.compact`  -> short pill for header / inline use
/// - `.tile`     -> larger card-like surface for grouped grids
struct ClickChip: View {
    enum Style { case compact, tile }

    let label: String
    let icon: String?
    let isActive: Bool
    let accent: Color
    var style: Style = .tile
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: style == .compact ? 5 : 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: style == .compact ? 9 : 11, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: style == .compact ? 10 : 12, weight: .medium))
            }
            .foregroundStyle(isActive ? accent : .secondary)
            .padding(.horizontal, style == .compact ? 9 : 12)
            .padding(.vertical, style == .compact ? 5 : 8)
            .frame(maxWidth: style == .tile ? .infinity : nil)
            .background(chipBackground)
            .scaleEffect(hovering ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hovering)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var chipBackground: some View {
        let radius: CGFloat = style == .compact ? 7 : 9
        RoundedRectangle(cornerRadius: radius)
            .fill(isActive ? accent.opacity(0.18) : Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(isActive ? accent.opacity(0.55) : Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

// MARK: - Reset Section Button

/// Bottom-of-section reset control with a destructive confirmation alert.
/// Shared across settings sub-sections so the visual + interaction is
/// identical everywhere. Caller passes the localised confirmation title and
/// the closure that performs the actual reset.
struct ResetSectionButton: View {
    let confirmTitle: String
    let onReset: () -> Void

    @State private var showAlert = false

    var body: some View {
        HStack {
            Spacer()
            Button(role: .destructive) {
                showAlert = true
            } label: {
                Text(String(localized: "settings.section.reset"))
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.Pastel.coral)
            .alert(confirmTitle, isPresented: $showAlert) {
                Button(String(localized: "settings.section.reset.cancel"), role: .cancel) { }
                Button(String(localized: "settings.section.reset.action"), role: .destructive) {
                    onReset()
                }
            }
        }
    }
}
