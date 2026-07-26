import SwiftUI

/// CMP-14 — Fuel's 4 log-method buttons (Scan/Photo/Search/Label, 46pt
/// glass circles). **Deliberately stubbed, per design-spec §1's own "Open
/// items" list**: "Scan/Photo/Search/Label log-method flows (4 buttons
/// render, no flow depicted)". This component references NO capability API
/// (`AVCaptureDevice`/`AVCaptureSession`, `PHPickerViewController`/
/// `PHPhotoLibrary`, `CLLocationManager`, `LAContext`,
/// `ATTrackingManager`) — only an SF Symbol glyph per method — so
/// `store-compliance.sh`'s SC-2 check (a capability API used without its
/// `NS…UsageDescription` string) stays inert for this component, matching
/// the task's explicit instruction. Wiring a REAL scan/photo/search flow
/// (and the resulting permission strings) is future scope, not this task's.
struct LogMethodButton: View {
    enum Method: String, CaseIterable, Identifiable {
        case scan = "Scan"
        case photo = "Photo"
        case search = "Search"
        case label = "Label"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .scan: return "barcode.viewfinder"
            case .photo: return "photo"
            case .search: return "magnifyingglass"
            case .label: return "tag"
            }
        }
    }

    let method: Method
    /// No-op by default — this button has no wired destination (see the
    /// type doc comment above).
    var onTap: (() -> Void)?

    /// Numerically the same as `Metrics.Radius.pillButtonHeight` (46pt) in
    /// this design, but kept as its own constant: a circle's diameter and a
    /// pill's height are conceptually unrelated tokens that merely coincide
    /// today, not a value that should silently move together if one design
    /// token changes later.
    private static let diameter: CGFloat = 46

    var body: some View {
        Button {
            onTap?()
        } label: {
            Image(systemName: method.symbolName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.Neutral.textPrimary)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Theme.Neutral.chipFill)
                .overlay(Circle().stroke(Theme.Neutral.cardBorder, lineWidth: 1))
                .clipShape(Circle())
        }
        .buttonStyle(PressableScaleButtonStyle(scale: Metrics.Motion.pressScale))
        .accessibilityLabel(method.rawValue)
    }
}
