import SwiftUI

/// A shared "press → scale down" button style (NM-4: "`:active` →
/// `.scaleEffect` on press") used by several CMP components — `Avatar`
/// (CMP-4, 0.9), `GradientPillButton` (CMP-7, 0.98), `PlanetPickerChip`
/// (CMP-10, 0.94), `QuickAddChip` (CMP-11, 0.95), `LogMethodButton`
/// (CMP-14, 0.95), `SetCircle` (CMP-17, 0.9). Each supplies its own
/// design-specified scale via `Metrics.Motion`'s already-centralized
/// press-scale family, rather than six near-identical private
/// `ButtonStyle` structs differing only in one number (rule of two/five —
/// code-standards' "no speculative abstraction, but a REAL second/third/
/// Nth case earns the shared type").
struct PressableScaleButtonStyle: ButtonStyle {
    let scale: CGFloat
    var duration: Double = Metrics.Motion.fillDuration

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: duration), value: configuration.isPressed)
    }
}
