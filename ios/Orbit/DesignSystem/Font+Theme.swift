import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Type-face family for one `OrbitTextStyle` (design-spec §3.5: "Display / numbers /
/// wordmark" → Space Grotesk, "Body / UI" → DM Sans). This is the ONE place that
/// knows whether the licensed `.ttf` is actually bundled (`UIAppFonts` — see
/// `FONTS-TODO.md`) or whether the app is running on the recorded SF substitute
/// (plan.md Open Question 6 default: SF Pro Rounded for display, SF Pro for body).
enum OrbitFontFamily: Sendable {
    case display
    case body

    var postScriptNameRegular: String {
        switch self {
        case .display: return "SpaceGrotesk-Regular"
        case .body: return "DMSans-Regular"
        }
    }

    var postScriptNameSemibold: String {
        switch self {
        case .display: return "SpaceGrotesk-SemiBold"
        case .body: return "DMSans-Medium"
        }
    }

    var postScriptNameBold: String {
        switch self {
        case .display: return "SpaceGrotesk-Bold"
        case .body: return "DMSans-Bold"
        }
    }

    func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black:
            return postScriptNameBold
        case .semibold, .medium:
            return postScriptNameSemibold
        default:
            return postScriptNameRegular
        }
    }

    /// The recorded SF substitute design (plan.md Open Question 6 default) this
    /// family falls back to when its `.ttf` isn't registered.
    var systemDesign: Font.Design {
        switch self {
        case .display: return .rounded // "SF Pro Rounded"
        case .body: return .default // "SF Pro"
        }
    }

    /// Checked at runtime, never assumed true — on this Linux build host there is
    /// no Xcode/toolchain to embed the `.ttf` files at all (see `FONTS-TODO.md` and
    /// `.pipeline/implementation-progress.md`'s T11 entry), so this always resolves
    /// `false` here; on a real device/simulator build with the fonts bundled it
    /// resolves `true` automatically, with no code change required.
    var isEmbedded: Bool {
        #if canImport(UIKit)
        return UIFont(name: postScriptNameRegular, size: 12) != nil
        #else
        return false
        #endif
    }
}

/// One named type-ramp entry (design-spec §3.5). Fixed px sizes from the design are
/// anchored to a Dynamic-Type text style via `relativeTextStyle` so the whole ladder
/// scales proportionally (plan §Frontend: "Dynamic Type scales the whole ladder
/// proportionally").
enum OrbitTextStyle: Equatable, Sendable {
    case wordmark
    case screenTitle
    case bigStatFuelRemaining
    case bigStatTrainScore
    case bigStatHomeCalRemaining
    case bigStatHomeStat
    case cardTitle
    case body
    case caption
    case sectionLabel
    case micro

    var family: OrbitFontFamily {
        switch self {
        case .wordmark, .bigStatFuelRemaining, .bigStatTrainScore, .bigStatHomeCalRemaining, .bigStatHomeStat:
            return .display
        case .screenTitle, .cardTitle, .body, .caption, .sectionLabel, .micro:
            return .body
        }
    }

    var size: CGFloat {
        switch self {
        case .wordmark: return 14
        case .screenTitle: return 25
        case .bigStatFuelRemaining: return 34
        case .bigStatTrainScore: return 40
        case .bigStatHomeCalRemaining: return 26
        case .bigStatHomeStat: return 24
        case .cardTitle: return 19
        case .body: return 13
        case .caption: return 11
        case .sectionLabel: return 10.5
        case .micro: return 9
        }
    }

    var weight: Font.Weight {
        switch self {
        case .wordmark: return .bold // 700
        case .screenTitle: return .semibold // 600
        case .bigStatFuelRemaining, .bigStatTrainScore, .bigStatHomeCalRemaining, .bigStatHomeStat:
            return .bold // 700
        case .cardTitle: return .semibold // 600
        case .body, .caption, .micro: return .regular
        case .sectionLabel: return .semibold // 600
        }
    }

    /// Letter-spacing in **em** (design-spec §3.5), converted to points via
    /// `.tracking(em * size)` at the call site (CSS `letter-spacing` is em-relative
    /// to the element's own font size, so it must scale with `size`, not be a fixed
    /// point value).
    var trackingEm: Double {
        switch self {
        case .wordmark: return 0.24
        case .screenTitle: return -0.01
        case .sectionLabel: return 0.18
        default: return 0
        }
    }

    var isUppercase: Bool {
        self == .sectionLabel
    }

    var relativeTextStyle: Font.TextStyle {
        switch self {
        case .wordmark: return .caption2
        case .screenTitle: return .title2
        case .bigStatFuelRemaining, .bigStatTrainScore: return .largeTitle
        case .bigStatHomeCalRemaining, .bigStatHomeStat: return .title
        case .cardTitle: return .title3
        case .body: return .subheadline
        case .caption: return .caption
        case .sectionLabel: return .caption2
        case .micro: return .caption2
        }
    }
}

extension Font {
    /// Resolves one `OrbitTextStyle` token to a concrete, Dynamic-Type-relative
    /// `Font` — the licensed Space Grotesk/DM Sans face when bundled, else the
    /// recorded SF Pro Rounded/SF Pro substitute, both scaled through the same
    /// `relativeTo`/`UIFontMetrics` mechanism so swapping the font source never
    /// changes how the ladder scales.
    static func orbit(_ style: OrbitTextStyle) -> Font {
        let family = style.family
        if family.isEmbedded {
            return .custom(family.postScriptName(for: style.weight), size: style.size, relativeTo: style.relativeTextStyle)
        }
        return systemSubstitute(for: style, family: family)
    }

    /// The recorded SF substitute path (plan.md Open Question 6 default), built the
    /// same documented way Apple's own HIG sample code builds a "fixed size, custom
    /// design, still Dynamic-Type-relative" system font: a `systemFont(ofSize:
    /// weight:)` re-described with the target `Font.Design`, then scaled through
    /// `UIFontMetrics` for the requested text style.
    private static func systemSubstitute(for style: OrbitTextStyle, family: OrbitFontFamily) -> Font {
        #if canImport(UIKit)
        let uiTextStyle = style.relativeTextStyle.uiKitTextStyle
        let baseFont = UIFont.systemFont(ofSize: style.size, weight: style.weight.uiKitWeight)
        // `UIFontDescriptor.withDesign(_:)` takes `UIFontDescriptor.SystemDesign`,
        // a DIFFERENT type from SwiftUI's `Font.Design` used in the `#else`
        // branch below — bridge explicitly rather than assuming they're
        // interchangeable (they share case names but not a type).
        let designedDescriptor = baseFont.fontDescriptor.withDesign(family.systemDesign.uiKitSystemDesign)
        let designedFont = designedDescriptor.map { UIFont(descriptor: $0, size: style.size) } ?? baseFont
        let scaledFont = UIFontMetrics(forTextStyle: uiTextStyle).scaledFont(for: designedFont)
        return Font(scaledFont)
        #else
        return .system(size: style.size, weight: style.weight, design: family.systemDesign)
        #endif
    }
}

#if canImport(UIKit)
private extension Font.Design {
    /// Bridges SwiftUI's `Font.Design` to UIKit's `UIFontDescriptor.SystemDesign`
    /// (same case names, distinct types — no built-in conversion).
    var uiKitSystemDesign: UIFontDescriptor.SystemDesign {
        switch self {
        case .default: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        @unknown default: return .default
        }
    }
}

private extension Font.Weight {
    /// `Font.Weight` has no public bridge to `UIFont.Weight` — map the finite set
    /// this design system actually uses (SwiftUI's own cases).
    var uiKitWeight: UIFont.Weight {
        switch self {
        case .black: return .black
        case .heavy: return .heavy
        case .bold: return .bold
        case .semibold: return .semibold
        case .medium: return .medium
        case .light: return .light
        case .thin: return .thin
        case .ultraLight: return .ultraLight
        default: return .regular
        }
    }
}

private extension Font.TextStyle {
    /// `Font.TextStyle` (SwiftUI) and `UIFont.TextStyle` (UIKit) name the same
    /// Dynamic Type ramp under different types — bridge the cases this design
    /// system uses so `UIFontMetrics` can scale the SF substitute correctly.
    var uiKitTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}
#endif
