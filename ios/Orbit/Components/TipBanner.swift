import SwiftUI

/// CMP-16 — Body's secondary-tinted tip banner (e.g. "**Tip:** log sets on
/// Train and trained muscles glow here"). Renders via the SAME
/// `TintedBanner` shared shape `CoachBanner.swift` (CMP-15) defines — two
/// distinct CMP ids, one rendering implementation.
struct TipBanner: View {
    let leadIn: String
    let message: String
    var theme = Theme()

    var body: some View {
        TintedBanner(leadIn: leadIn, message: message, tint: theme.secondary)
            .accessibilityElement(children: .combine)
    }
}
