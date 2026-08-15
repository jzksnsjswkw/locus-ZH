import SwiftUI

enum LocusTheme {
    static let accent = Color(red: 0.35, green: 0.78, blue: 0.72)
    static let accentSecondary = Color(red: 0.95, green: 0.55, blue: 0.28)
    static let danger = Color(red: 0.92, green: 0.32, blue: 0.36)
    static let panelStroke = Color.white.opacity(0.12)
    static let statusGood = Color(red: 0.30, green: 0.86, blue: 0.55)
    static let statusWarn = Color(red: 0.98, green: 0.78, blue: 0.28)
    static let statusBad = Color(red: 0.92, green: 0.32, blue: 0.36)
}

enum LocusGlassStyle {
    case regular
    case clear
    case interactive
}

/// A transparent presentation surface that lets the map remain visible.
/// On iOS 26+ this is real Liquid Glass; older systems use a material fallback.
private struct LocusSheetGlassBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var isExpanded: Bool

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: Rectangle())
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(expandedReadabilityTint)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    private var expandedReadabilityTint: Color {
        guard isExpanded else { return .clear }
        return colorScheme == .dark
            ? Color.black.opacity(0.20)
            : Color.white.opacity(0.14)
    }
}

/// A stronger blur reserved for grouped rows so text stays readable while the
/// surrounding sheet continues to show the map through the glass.
private struct LocusSheetRowBackground: View {
    var body: some View {
        Rectangle()
            .fill(.regularMaterial)
    }
}

/// Liquid Glass on iOS 26+; material fallback earlier.
struct LocusGlassModifier<S: Shape>: ViewModifier {
    var style: LocusGlassStyle
    var shape: S
    var tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(glass, in: shape)
                // Glass draws outside the layout bounds; expand hit-testing to match.
                .contentShape(shape)
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.55))
                    }
                }
                .overlay(shape.stroke(LocusTheme.panelStroke, lineWidth: 1))
                .contentShape(shape)
        }
    }

    @available(iOS 26.0, *)
    private var glass: Glass {
        var g: Glass = style == .clear ? .clear : .regular
        // Every glass surface should react to a sustained touch. Keeping this
        // in the shared modifier avoids adding competing long-press gestures
        // to buttons, map annotations and text fields.
        g = g.interactive()
        if let tint { g = g.tint(tint) }
        return g
    }
}

extension View {
    func locusGlass<S: Shape>(
        _ style: LocusGlassStyle = .regular,
        tint: Color? = nil,
        in shape: S
    ) -> some View {
        modifier(LocusGlassModifier(style: style, shape: shape, tint: tint))
    }

    func locusGlass(_ style: LocusGlassStyle = .regular, tint: Color? = nil) -> some View {
        locusGlass(style, tint: tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    func locusSheetPresentation(isExpanded: Bool) -> some View {
        background {
            LocusSheetGlassBackground(isExpanded: isExpanded)
        }
        .presentationBackground(.clear)
    }

    /// Keeps grouped sheet rows readable without making the whole sheet opaque.
    func locusSheetRows() -> some View {
        listRowBackground(LocusSheetRowBackground())
    }
}
