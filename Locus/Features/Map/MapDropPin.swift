import MapKit
import SwiftUI

/// Map pin with Liquid Glass “Remove Pin” menu and long-press drag.
struct MapDropPin: View {
    var selected: Bool
    var isDragging: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void
    var onDragBegan: () -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: () -> Void
    @State private var tapScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .bottom) {
            RedSelectionPin()
                .frame(width: 36, height: 48)
                .frame(width: 44, height: 48, alignment: .bottom)
                .shadow(color: .black.opacity(0.35), radius: isDragging ? 8 : 4, y: 2)
                .scaleEffect(tapScale * (isDragging ? 1.12 : 1), anchor: .bottom)
                .onTapGesture {
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
                Button(action: onRemove) {
                    Label("删除图钉", systemImage: "trash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LocusTheme.danger)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .locusGlass(.regular, in: Capsule())
                .contentShape(Capsule())
                .fixedSize()
                .offset(y: -56)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 44, height: 48, alignment: .bottom)
        // The menu is an offset overlay, so selection never changes annotation size.
        .padding(.bottom, 2)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: selected)
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(selected ? "已选图钉" : "地图图钉")
        .accessibilityHint("轻点以显示删除按钮，长按可拖动。")
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
                        if !isDragging {
                            onDragBegan()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        onDragMoved(drag.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                onDragEnded()
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
