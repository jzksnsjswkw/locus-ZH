import MapKit
import SwiftUI

/// Draggable map pin with an in-bounds action menu. Keeping the menu inside the
/// annotation's fixed frame prevents its buttons from falling through to Map.
struct MapDropPin: View {
    var selected: Bool
    var expandedActions: Bool
    var isDragging: Bool
    var onSelect: () -> Void
    var onShowExpandedActions: () -> Void
    var onRemove: () -> Void
    var onBuildRouteToPin: () -> Void
    var onDragBegan: () -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: () -> Void
    @State private var tapScale: CGFloat = 1
    @State private var draggingFromLongPress = false
    @State private var longPressActivated = false
    @State private var suppressTapAfterLongPress = false
    @State private var isPressing = false
    @State private var pressFeedbackSent = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RedSelectionPin()
                .frame(width: 36, height: 48)
                .frame(width: 44, height: 48, alignment: .bottom)
                .shadow(color: .black.opacity(0.35), radius: isDragging ? 8 : 4, y: 2)
                .scaleEffect(
                    tapScale * (isDragging ? 1.12 : 1) * (isPressing ? 0.94 : 1),
                    anchor: .bottom
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !suppressTapAfterLongPress else { return }
                    withAnimation(.easeOut(duration: 0.08)) {
                        tapScale = 0.88
                    }
                    onSelect()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                            tapScale = 1
                        }
                    }
                }
                .onLongPressGesture(
                    minimumDuration: 0.5,
                    maximumDistance: 20,
                    pressing: handlePressing,
                    perform: activateLongPress
                )
                .simultaneousGesture(dragGesture)

            if selected && !isDragging {
                pinActionMenu
                .offset(y: -56)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
        }
        // The frame never changes, so the red pin tip stays fixed while menus open.
        .frame(width: 200, height: 102, alignment: .bottom)
        .allowsHitTesting(true)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selected)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: expandedActions)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: isPressing)
    }

    private var pinActionMenu: some View {
        HStack(spacing: 0) {
            actionButton("删除", systemImage: "trash.fill", color: LocusTheme.danger, width: 78, action: onRemove)
            if expandedActions {
                Divider()
                    .overlay(Color.white.opacity(0.25))
                    .frame(height: 28)
                actionButton("生成轨迹", systemImage: SFSymbolCompat.resolved("road.lanes"), color: .blue, width: 112, action: onBuildRouteToPin)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .locusGlass(.regular, in: Capsule())
        .contentShape(Rectangle())
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        color: Color = .primary,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        // Plain Button hit-testing degenerates to rendered glyphs on real
        // devices above MKMapView; a direct tap gesture honors contentShape.
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: width, height: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                guard longPressActivated else { return }
                let distance = max(abs(value.translation.width), abs(value.translation.height))
                guard distance >= 8 else { return }
                if !draggingFromLongPress {
                    draggingFromLongPress = true
                    onDragBegan()
                }
                onDragMoved(value.location)
            }
            .onEnded { _ in
                let wasActivated = longPressActivated
                if draggingFromLongPress {
                    onDragEnded()
                }
                if wasActivated {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        suppressTapAfterLongPress = false
                    }
                }
                draggingFromLongPress = false
                longPressActivated = false
            }
    }

    private func handlePressing(_ pressing: Bool) {
        isPressing = pressing
        if pressing, !pressFeedbackSent {
            pressFeedbackSent = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } else if !pressing {
            pressFeedbackSent = false
        }
    }

    private func activateLongPress() {
        guard !longPressActivated else { return }
        longPressActivated = true
        suppressTapAfterLongPress = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onShowExpandedActions()
    }
}

private struct RedSelectionPin: View {
    var body: some View {
        ZStack(alignment: .top) {
            SelectionPinShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.29, blue: 0.25),
                            Color(red: 0.78, green: 0.03, blue: 0.07)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    SelectionPinShape()
                        .stroke(.white.opacity(0.95), lineWidth: 2)
                }

            Circle()
                .fill(.white)
                .frame(width: 11, height: 11)
                .overlay {
                    Circle().stroke(Color.red.opacity(0.25), lineWidth: 1)
                }
                .padding(.top, 10)
        }
    }
}

private struct SelectionPinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: width * 0.5, y: 0))
        path.addCurve(
            to: CGPoint(x: width, y: height * 0.37),
            control1: CGPoint(x: width * 0.79, y: 0),
            control2: CGPoint(x: width, y: height * 0.14)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: height),
            control1: CGPoint(x: width, y: height * 0.62),
            control2: CGPoint(x: width * 0.66, y: height * 0.81)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: height * 0.37),
            control1: CGPoint(x: width * 0.34, y: height * 0.81),
            control2: CGPoint(x: 0, y: height * 0.62)
        )
        path.addCurve(
            to: CGPoint(x: width * 0.5, y: 0),
            control1: CGPoint(x: 0, y: height * 0.14),
            control2: CGPoint(x: width * 0.21, y: 0)
        )
        path.closeSubpath()
        return path
    }
}
