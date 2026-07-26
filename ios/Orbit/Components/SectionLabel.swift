import SwiftUI

/// CMP-2 — the section-header label every card uses (design-spec §3:
/// 10.5pt, semibold, 0.18em tracking, uppercase, muted). Uppercasing is
/// applied here directly (SwiftUI has no `text-transform` modifier) rather
/// than gated on `OrbitTextStyle.sectionLabel.isUppercase`, since this type
/// IS the one caller of that style that always wants it uppercase.
struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.orbit(.sectionLabel))
            .tracking(OrbitTextStyle.sectionLabel.trackingEm * OrbitTextStyle.sectionLabel.size)
            .foregroundStyle(Theme.Neutral.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}
