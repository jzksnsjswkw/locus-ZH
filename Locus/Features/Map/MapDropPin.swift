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
    @State private var suppressTapAfterLongPress = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RedSelectionPin()
                .frame(width: 36, height: 48)
                .frame(width: 44, height: 48, alignment: .bottom)
                .shadow(color: .black.opacity(0.35), radius: isDragging ? 8 : 4, y: 2)
                .scaleEffect(tapScale * (isDragging ? 1.12 : 1), anchor: .bottom)
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
                .gesture(dragGesture)

            if selected && !isDragging {
                pinActionMenu
                .offset(y: -56)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
        }
        // The frame never changes, so the red pin tip stays fixed while menus open.
        .frame(width: 200, height: 102, alignment: .bottom)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selected)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: expandedActions)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    private var pinActionMenu: some View {
        HStack(spacing: 4) {
            actionButton("删除", systemImage: "trash.fill", color: LocusTheme.danger, action: onRemove)
            if expandedActions {
                actionButton("生成轨迹", systemImage: "road.lanes", color: .blue, action: onBuildRouteToPin)
            }
        }
        .padding(3)
        .locusGlass(.regular, in: Capsule())
        .contentShape(Capsule())
        .fixedSize()
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        color: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 6)
                .frame(height: 30)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let drag):
                    if let drag {
                        let distance = max(abs(drag.translation.width), abs(drag.translation.height))
                        guard distance >= 8 else { break }
                        if !draggingFromLongPress {
                            draggingFromLongPress = true
                            onDragBegan()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        onDragMoved(drag.location)
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                if case .second(true, _) = value {
                    suppressTapAfterLongPress = true
                    if draggingFromLongPress {
                        onDragEnded()
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onShowExpandedActions()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        suppressTapAfterLongPress = false
                    }
                }
                draggingFromLongPress = false
            }
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
