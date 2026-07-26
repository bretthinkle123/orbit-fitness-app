import Foundation
import SwiftUI

/// The ONE place a hex string is ever turned into a `Color` (CLAUDE.md "no hardcoded
/// hues outside the palette definitions"). Every palette-derived color in `Theme`
/// flows through this initializer; screens/components never call it directly with a
/// literal — they read a `Theme` property instead.
extension Color {
    /// Builds a `Color` from a `#RRGGBB` or `#RRGGBBAA` hex string (case-insensitive,
    /// leading `#` optional). Malformed input falls back to opaque black rather than
    /// crashing — this initializer only ever receives values already validated
    /// against `Theme`'s own hex-format tests, never raw user input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch cleaned.count {
        case 8:
            red = Double((value >> 24) & 0xFF) / 255
            green = Double((value >> 16) & 0xFF) / 255
            blue = Double((value >> 8) & 0xFF) / 255
            alpha = Double(value & 0xFF) / 255
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
            alpha = 1
        default:
            red = 0
            green = 0
            blue = 0
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
