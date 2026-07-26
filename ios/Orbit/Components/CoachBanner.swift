import SwiftUI

/// CMP-15 — Fuel's secondary-tinted coach banner (e.g. "**Mission
/// Control:** burn rate trending up…"). Distinct CMP id from `TipBanner`
/// (CMP-16, Body) even though both render the SAME visual shape — see
/// `TintedBanner` (this file) for the shared rendering.
struct CoachBanner: View {
    let leadIn: String
    let message: String
    var theme = Theme()

    var body: some View {
        TintedBanner(leadIn: leadIn, message: message, tint: theme.secondary)
            .accessibilityElement(children: .combine)
    }
}

/// Shared rendering for CMP-15 `CoachBanner` / CMP-16 `TipBanner` — both are
/// "secondary-tinted info banner" per the component inventory
/// (`.pipeline/design-spec.md` §2), differing only in which screen/copy
/// uses them, not in visual shape.
struct TintedBanner: View {
    let leadIn: String
    let message: String
    let tint: Color

    var body: some View {
        (Text(leadIn).bold() + Text(" " + message))
            .font(.orbit(.body))
            .foregroundStyle(Theme.Neutral.textPrimary)
            .padding(Metrics.Spacing.cardPaddingMin)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .circular)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Metrics.Radius.card, style: .circular))
    }
}
