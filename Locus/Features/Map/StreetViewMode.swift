import MapKit
import SwiftUI
import UIKit

struct StreetViewMode: View {
    @Binding var scene: MKLookAroundScene?
    let confirmedCoordinate: CLLocationCoordinate2D
    let namespace: Namespace.ID
    let onMapCenterChanged: (CLLocationCoordinate2D) -> Void
    let onDone: () -> Void

    @State private var mapPosition: MapCameraPosition
    @State private var currentRegion: MKCoordinateRegion
    @State private var currentCamera: MapCamera?
    @State private var isThreeDimensional = false
    @State private var showFullScreenViewer = false

    init(
        scene: Binding<MKLookAroundScene?>,
        confirmedCoordinate: CLLocationCoordinate2D,
        namespace: Namespace.ID,
        onMapCenterChanged: @escaping (CLLocationCoordinate2D) -> Void,
        onDone: @escaping () -> Void
    ) {
        _scene = scene
        self.confirmedCoordinate = confirmedCoordinate
        self.namespace = namespace
        self.onMapCenterChanged = onMapCenterChanged
        self.onDone = onDone
        let region = MKCoordinateRegion(
            center: confirmedCoordinate,
            latitudinalMeters: 900,
            longitudinalMeters: 900
        )
        _mapPosition = State(initialValue: .region(region))
        _currentRegion = State(initialValue: region)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if scene != nil {
                            LookAroundPreview(
                                scene: $scene,
                                allowsNavigation: true,
                                showsRoadLabels: true,
                                pointsOfInterest: .all,
                                badgePosition: .bottomTrailing
                            )
                        } else {
                            ZStack {
                                Color(uiColor: .secondarySystemBackground)
                                VStack(spacing: 10) {
                                    ProgressView()
                                    Text("正在加载街景…")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .matchedGeometryEffect(id: "streetPreview", in: namespace)

                    HStack(spacing: 8) {
                        Button {
                            showFullScreenViewer = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .frame(width: 42, height: 42)
                        }
                        .disabled(scene == nil)
                        .accessibilityLabel("全屏查看街景")

                        Button("完成", action: onDone)
                            .font(.subheadline.weight(.semibold))
                            .frame(height: 42)
                            .padding(.horizontal, 4)
                            .accessibilityLabel("退出街景")
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .locusGlass(.clear, in: Capsule())
                    .padding(.top, 8)
                    .padding(.trailing, 12)
                }
                .frame(height: max(280, geometry.size.height * 0.48))
                .clipShape(
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 26,
                        bottomTrailingRadius: 26,
                        style: .continuous
                    )
                )
                .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
                .zIndex(1)

                ZStack(alignment: .bottomTrailing) {
                    Map(position: $mapPosition) {
                        MapCircle(center: confirmedCoordinate, radius: 55)
                            .foregroundStyle(Color.blue.opacity(0.16))
                        MapCircle(center: confirmedCoordinate, radius: 55)
                            .stroke(Color.blue, lineWidth: 3)
                        Annotation("已确认街景", coordinate: confirmedCoordinate) {
                            Image(systemName: "binoculars.fill")
                                .font(.body.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Color.blue))
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .mapControlVisibility(.hidden)
                    .onMapCameraChange(frequency: .onEnd) { context in
                        currentRegion = context.region
                        currentCamera = context.camera
                        onMapCenterChanged(context.region.center)
                    }

                    VStack(alignment: .trailing, spacing: 10) {
                        Text("蓝色标记为已确认街景位置")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .locusGlass(.clear, in: Capsule())

                        VStack(spacing: 0) {
                            Button(action: faceNorth) {
                                Image(systemName: "location.north.line.fill")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 48, height: 48)
                            }
                            .accessibilityLabel("地图回正北")

                            Divider()
                                .overlay(Color.white.opacity(0.22))
                                .frame(width: 32)

                            Button(action: toggleDimension) {
                                Text(isThreeDimensional ? "2D" : "3D")
                                    .font(.subheadline.weight(.bold))
                                    .frame(width: 48, height: 48)
                            }
                            .accessibilityLabel(isThreeDimensional ? "切换为二维地图" : "切换为三维地图")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                        .padding(4)
                        .locusGlass(.clear, in: Capsule())
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.black)
        .lookAroundViewer(isPresented: $showFullScreenViewer, initialScene: scene)
        .accessibilityElement(children: .contain)
    }

    private func faceNorth() {
        let camera = currentCamera ?? fallbackCamera
        withAnimation(.easeInOut(duration: 0.3)) {
            mapPosition = .camera(MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: camera.distance,
                heading: 0,
                pitch: camera.pitch
            ))
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func toggleDimension() {
        isThreeDimensional.toggle()
        let camera = currentCamera ?? fallbackCamera
        withAnimation(.easeInOut(duration: 0.35)) {
            mapPosition = .camera(MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: camera.distance,
                heading: camera.heading,
                pitch: isThreeDimensional ? 60 : 0
            ))
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var fallbackCamera: MapCamera {
        MapCamera(
            centerCoordinate: currentRegion.center,
            distance: max(250, currentRegion.span.latitudeDelta * 111_000),
            heading: 0,
            pitch: isThreeDimensional ? 60 : 0
        )
    }
}
