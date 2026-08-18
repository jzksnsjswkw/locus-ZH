import SwiftUI

/// First-run walkthrough: welcome → map.
/// Skipped when `SetupGate.isComplete` (see `LocusApp`).
struct SetupFlowView: View {
    @EnvironmentObject private var session: SpoofSession

    var onFinished: () -> Void

    @State private var appear = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                welcomePage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { appear = true }
            pulse = true
        }
        .alert("Locus", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("确定", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Soft map-adjacent atmosphere (no flat fill).
            RadialGradient(
                colors: [
                    LocusTheme.accent.opacity(0.22),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.18, blue: 0.28).opacity(0.9),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            // Subtle grid suggestion of a map without competing with copy.
            GeometryReader { geo in
                Path { path in
                    let spacing: CGFloat = 44
                    for x in stride(from: 0, through: geo.size.width, by: spacing) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    }
                    for y in stride(from: 0, through: geo.size.height, by: spacing) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(LocusTheme.accent.opacity(pulse ? 0 : 0.18))
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.35 : 0.9)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: pulse)
                        .opacity(appear ? 1 : 0)

                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(LocusTheme.accent)
                        .opacity(appear ? 1 : 0)
                        .scaleEffect(appear ? 1 : 0.85)
                }

                VStack(spacing: 10) {
                    Text("Locus")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .tracking(-0.5)

                    Text("瞬移到任意位置。\n无需电脑。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Text("通过 TrollStore 安装后即可开始模拟定位。")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                primaryButton("开始使用") {
                    onFinished()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .opacity(appear ? 1 : 0)
        }
    }

    // MARK: - Shared

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Capsule().fill(LocusTheme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Gate

enum SetupGate {
    static let defaultsKey = "locus.setupComplete"
    static let inProgressKey = "locus.setupInProgress"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var isInProgress: Bool {
        UserDefaults.standard.bool(forKey: inProgressKey)
    }

    static func markInProgress() {
        UserDefaults.standard.set(true, forKey: inProgressKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        UserDefaults.standard.set(false, forKey: inProgressKey)
    }
}