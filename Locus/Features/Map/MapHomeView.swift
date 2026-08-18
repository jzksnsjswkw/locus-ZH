import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase
    @Binding var showPlaces: Bool
    @Binding var favoriteRenameSuggestion: SavedPlace?
    @Binding var searchPresented: Bool
    @Binding var showRouteSheet: Bool
    @Binding var generatedRouteReady: Bool
    @Binding var routeOptions: [PlannedRoute]
    @Binding var selectedRouteOptionID: UUID?
    @Binding var drawingRouteActive: Bool
    @Binding var drawingRoutePointCount: Int

    @StateObject private var search = PlaceSearchCompleter()
    @StateObject private var mapDataSourceDetector = MapDataSourceDetector()
    @Namespace private var rightLowerControlNamespace
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        latitudinalMeters: 2000,
        longitudinalMeters: 2000
    )
    /// Bumped by the locate button so LocusMapView eases the camera over 0.35s.
    @State private var animateRegionToken = 0
    @State private var mapView: MKMapView?
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var routeWaypoints: [CLLocationCoordinate2D] = []
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeIsHandDrawn = false
    @State private var edgeZoomStartRegion: MKCoordinateRegion?
    @State private var lastLocationButtonTap: Date?
    @State private var isRouting = false
    @State private var showGPXImporter = false
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var drawnRouteStart: CLLocationCoordinate2D?
    @State private var drawnRouteEnd: CLLocationCoordinate2D?
    @State private var pinSelected = false
    @State private var pinExpandedActions = false
    @State private var selectedFavoriteID: String?
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    @State private var favoriteToast: String?
    @State private var favoriteToastTask: Task<Void, Never>?
    @State private var searchNamedCoordinate: CLLocationCoordinate2D?
    @State private var confirmClearSearchHistory = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?
    /// Bumped once the map region settles so the marker overlays re-evaluate their
    /// converted points against the final viewport (search-placed pins land
    /// off-screen otherwise, because the body re-renders before updateUIView
    /// applies the new region).
    @State private var regionSettledToken = 0

    private var mapType: MKMapType {
        switch session.mapStyleIndex {
        case 1: return .hybrid
        case 2: return .satellite
        default: return .standard
        }
    }

    var body: some View {
        presentedMap
    }

    private var mapSurface: some View {
        ZStack(alignment: .top) {
            mapLayer

            if session.targetSelectionMode == .crosshair, !drawMode, !searchPresented {
                crosshairTarget
                    .zIndex(2)
            }

            topChrome
                .zIndex(3)

            if !searchPresented {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        rightLowerDynamicControl
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, bottomControlClearance)
                }
                .allowsHitTesting(true)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: session.routeActive)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: session.routePaused)
                .zIndex(2)
            }

            if searchPresented {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if searchText.isEmpty, session.searchHistoryEnabled, !session.searchHistory.isEmpty {
                        searchHistoryResults
                    } else if !searchText.isEmpty && !search.results.isEmpty {
                        searchResults
                    }
                    searchBar
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(4)
            }

            if let favoriteToast {
                Text(favoriteToast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .locusGlass(.regular, in: Capsule())
                    .padding(.top, 154)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
    }

    /// Map + marker overlays share one coordinate space so MKMapView point
    /// conversions line up with SwiftUI `.position`. The map stays inside the
    /// safe layout bounds so conversions match finger position — ignoring the
    /// safe area would make the tiles full-bleed but shift conversions upward
    /// by ~status-bar height.
    private var mapLayer: some View {
        ZStack {
            LocusMapView(
                region: $region,
                mapType: mapType,
                animateRegionToken: animateRegionToken,
                simulated: session.simulated,
                routeCoords: routeCoords,
                routeColor: mainRouteColor,
                routeLineWidth: mainRouteLineWidth,
                routeDashed: mainRouteDashed,
                alternativeRouteCoords: alternativeRouteCoords,
                drawnPath: drawnPath,
                onMapViewCreated: { mapView in
                    // makeUIView runs during SwiftUI's view-update phase;
                    // writing @State here is dropped, so defer to the next runloop.
                    DispatchQueue.main.async {
                        self.mapView = mapView
                    }
                },
                onMapTap: handleMapTap,
                onMapLongPress: handleMapLongPress,
                onRegionSettled: handleRegionSettled
            )
            // Fill the container explicitly: a UIViewRepresentable has no
            // intrinsic size, and in a ZStack it can collapse to zero frame
            // on iOS 16 (sizeThatFits behavior), leaving a black screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            simulatedMarkerOverlay
            favoriteMarkersOverlay
            pinOverlay
            waypointMarkersOverlay
            routeEndpointMarkersOverlay

            MapDataSourceProbe(detector: mapDataSourceDetector)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var mapLifecycle: some View {
        mapSurface
        .onAppear {
            session.startLocationUpdates()
            generatedRouteReady = routeReadyState
            drawingRouteActive = drawMode
            drawingRoutePointCount = drawnPath.count
            if session.restoreLastMapView, let saved = session.savedMapRegion() {
                region = saved
                if session.targetSelectionMode == .crosshair {
                    session.crosshairCoordinate = saved.center
                }
            } else if session.targetSelectionMode == .crosshair,
                      session.crosshairCoordinate == nil {
                session.crosshairCoordinate = session.pin ?? session.simulated ?? session.realMapCoordinate
            }
        }
        .onChange(of: routeReadyState) { ready in
            generatedRouteReady = ready
        }
        .onChange(of: drawMode) { active in
            drawingRouteActive = active
        }
        .onChange(of: drawnPath.count) { count in
            drawingRoutePointCount = count
        }
        .onDisappear {
            favoriteToastTask?.cancel()
            favoriteToastTask = nil
            favoriteToast = nil
            generatedRouteReady = false
            routeOptions.removeAll()
            selectedRouteOptionID = nil
            drawingRouteActive = false
            drawingRoutePointCount = 0
        }
    }

    private var mapInteractions: some View {
        mapLifecycle
        .onChange(of: searchPresented) { presented in
            if presented {
                pinSelected = false
                pinExpandedActions = false
                selectedFavoriteID = nil
                DispatchQueue.main.async {
                    searchFocused = true
                }
            } else {
                searchFocused = false
            }
        }
        .onChange(of: session.pin?.latitude) { newValue in
            if newValue == nil {
                pinSelected = false
                pinExpandedActions = false
            }
        }
        .onChange(of: session.status) { status in
            if case .idle = status {
                clearRoutePresentation()
            }
        }
    }

    private var mapRouteInteractions: some View {
        mapInteractions
        .onReceive(NotificationCenter.default.publisher(for: .locusImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusDeleteRoute)) { _ in
            deleteGeneratedRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusRunRoute)) { _ in
            runGeneratedRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusBuildRouteToTarget)) { _ in
            buildRouteToCurrentTarget()
        }
        .onChange(of: session.targetSelectionMode) { mode in
            closePinActions()
            if mode == .crosshair {
                session.crosshairCoordinate = session.pin ?? session.simulated ?? session.realMapCoordinate
            }
        }
        .onChange(of: selectedRouteOptionID) { selectedID in
            guard let selectedID,
                  let option = routeOptions.first(where: { $0.id == selectedID }) else { return }
            routeCoords = option.coordinates
        }
        .onChange(of: simulatedCoordinateKey) { _ in
            followSimulatedLocationIfNeeded()
        }
        .onChange(of: session.locationSummaryRevision) { _ in
            mapDataSourceDetector.redetect()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                mapDataSourceDetector.scheduleDetection()
            }
        }
    }

    private var presentedMap: some View {
        mapRouteInteractions
        .onReceive(NotificationCenter.default.publisher(for: .locusCancelDrawingRoute)) { _ in
            cancelDrawingRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusUndoDrawingPoint)) { _ in
            undoDrawingPoint()
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusSaveDrawingRoute)) { _ in
            saveDrawingRoute()
        }
        .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importGPX(url)
            }
        }
        .sheet(isPresented: $showRouteSheet) {
            RoutePlannerSheet(
                onPlay: playRoute,
                onImportGPX: { showGPXImporter = true },
                onExportGPX: exportGPX,
                onBuildRouteToTarget: {
                    showRouteSheet = false
                    buildRouteToCurrentTarget()
                },
                drawMode: drawMode,
                onToggleDrawing: {
                    if !drawMode {
                        beginDrawingRoute()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("清空搜索历史", isPresented: $confirmClearSearchHistory) {
            Button("清空", role: .destructive) { session.clearSearchHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    // MARK: - Marker overlays (positioned via MKMapView coordinate conversion)

    @ViewBuilder
    private var simulatedMarkerOverlay: some View {
        if let mapView, let sim = session.simulated {
            // Re-evaluate when the region settles so markers track the final viewport.
            let _ = regionSettledToken
            let point = mapView.convert(sim, toPointTo: mapView)
            ZStack {
                Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .position(x: point.x, y: point.y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var favoriteMarkersOverlay: some View {
        if let mapView {
            let _ = regionSettledToken
            ForEach(session.favorites) { favorite in
                let point = mapView.convert(favorite.coordinate, toPointTo: mapView)
                FavoriteMapMarker(
                    selected: selectedFavoriteID == favorite.id,
                    onSelect: {
                        dismissStatusDetails()
                        selectedFavoriteID = favorite.id
                        pinSelected = false
                        pinExpandedActions = false
                        if session.targetSelectionMode != .crosshair {
                            selectFavorite(favorite)
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    },
                    onLongPress: {
                        dismissStatusDetails()
                        pinSelected = false
                        pinExpandedActions = false
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            selectedFavoriteID = favorite.id
                        }
                    },
                    onRemove: {
                        removeFavoriteFromMap(favorite)
                    }
                )
                .accessibilityLabel(session.favoriteDisplayName(favorite))
                .accessibilityHint(session.targetSelectionMode == .crosshair
                                   ? "轻点显示删除按钮"
                                   : "半秒内松手可切换模拟位置，按住半秒显示删除按钮")
                // Mirrors the old Annotation anchor: UnitPoint(x: 0.5, y: 0.76).
                // The 160x92 frame is bottom-aligned; the anchor point sits
                // 0.76 * 92 = 69.92 from the top, i.e. 22.08 above the bottom edge.
                // Positioning the frame center at point.y - 24 puts that point
                // on the coordinate.
                .frame(width: 160, height: 92, alignment: .bottom)
                .position(x: point.x, y: point.y - 24)
            }
        }
    }

    @ViewBuilder
    private var pinOverlay: some View {
        if let mapView,
           session.targetSelectionMode == .pin,
           let pin = session.pin,
           session.favorite(at: pin) == nil {
            let _ = regionSettledToken
            let point = mapView.convert(pin, toPointTo: mapView)
            MapDropPin(
                selected: pinSelected,
                expandedActions: pinExpandedActions,
                isDragging: isDraggingPin,
                onSelect: {
                    dismissStatusDetails()
                    searchFocused = false
                    suppressNextMapTap = true
                    selectedFavoriteID = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        pinSelected = false
                        pinExpandedActions = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        suppressNextMapTap = false
                    }
                },
                onShowExpandedActions: {
                    dismissStatusDetails()
                    searchFocused = false
                    suppressNextMapTap = true
                    selectedFavoriteID = nil
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        pinSelected = true
                        pinExpandedActions = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        suppressNextMapTap = false
                    }
                },
                onRemove: {
                    dismissStatusDetails()
                    suppressNextMapTap = true
                    withAnimation {
                        session.pin = nil
                        pinSelected = false
                        pinExpandedActions = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        suppressNextMapTap = false
                    }
                },
                onBuildRouteToPin: buildRouteToCurrentTarget,
                onDragBegan: {
                    dismissStatusDetails()
                    searchFocused = false
                    suppressNextMapTap = true
                    pinPlaceName = nil
                    pinSelected = false
                    pinExpandedActions = false
                    isDraggingPin = true
                },
                onDragMoved: { globalPoint in
                    // MapDropPin drags report window coordinates; MKMapView
                    // converts those straight to a map coordinate.
                    session.pin = mapView.convert(globalPoint, toCoordinateFrom: nil)
                },
                onDragEnded: {
                    isDraggingPin = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        suppressNextMapTap = false
                    }
                }
            )
            // Anchor the pin tip on the coordinate: the 200x102 frame is
            // bottom-aligned and positioned so its bottom-center sits on the
            // converted point (mirrors the old Annotation anchor: .bottom).
            .frame(width: 200, height: 102, alignment: .bottom)
            .position(x: point.x, y: point.y - 51)
        }
    }

    @ViewBuilder
    private var waypointMarkersOverlay: some View {
        if let mapView {
            let _ = regionSettledToken
            ForEach(routeWaypoints.indices, id: \.self) { index in
                let point = mapView.convert(routeWaypoints[index], toPointTo: mapView)
                RouteWaypointMarker(number: index + 1)
                    .frame(width: 38, height: 44, alignment: .bottom)
                    .position(x: point.x, y: point.y - 22)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var routeEndpointMarkersOverlay: some View {
        if let mapView {
            let _ = regionSettledToken
            if let start = drawMode ? drawnPath.first : drawnRouteStart {
                let point = mapView.convert(start, toPointTo: mapView)
                RouteEndpointMarker(color: .green, systemImage: "play.fill")
                    .position(x: point.x, y: point.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if !drawMode, let end = drawnRouteEnd {
                let point = mapView.convert(end, toPointTo: mapView)
                RouteEndpointMarker(color: .red, systemImage: "stop.fill")
                    .position(x: point.x, y: point.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: - Map interactions

    private func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        dismissStatusDetails()
        searchFocused = false
        searchPresented = false
        guard !suppressNextMapTap, !isDraggingPin else { return }
        pinSelected = false
        pinExpandedActions = false
        selectedFavoriteID = nil
        placePin(at: coordinate)
    }

    private func handleMapLongPress(_ coordinate: CLLocationCoordinate2D) {
        guard !hitsInteractiveMarker(at: coordinate) else { return }
        if canAddRouteWaypoint,
           ChinaCoordinateTransform.usesMainlandChinaOffset(coordinate) {
            suppressNextMapTap = true
            routeWaypoints.append(coordinate)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showFavoriteToast("已添加途经点 \(routeWaypoints.count)，正在重新规划")
            buildRoadRoute()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                suppressNextMapTap = false
            }
        } else if session.targetSelectionMode == .pin {
            placeExpandedPin(at: coordinate)
        }
    }

    private func handleRegionSettled() {
        regionSettledToken += 1
        session.saveMapRegion(region)
        if session.targetSelectionMode == .crosshair {
            session.crosshairCoordinate = region.center
            if let named = searchNamedCoordinate,
               CLLocation(latitude: named.latitude, longitude: named.longitude)
                .distance(from: CLLocation(
                    latitude: region.center.latitude,
                    longitude: region.center.longitude
                )) > 15 {
                pinPlaceName = nil
                searchNamedCoordinate = nil
            }
        }
    }

    private func placePin(at coordinate: CLLocationCoordinate2D) {
        if drawMode {
            drawnPath.append(coordinate)
        } else if session.targetSelectionMode == .pin {
            session.pin = coordinate
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private func placeExpandedPin(at coordinate: CLLocationCoordinate2D) {
        guard session.targetSelectionMode == .pin,
              !drawMode,
              !suppressNextMapTap,
              !isDraggingPin else { return }
        if let pin = session.pin, let mapView {
            let anchor = mapView.convert(pin, toPointTo: mapView)
            let pinHitArea = CGRect(
                x: anchor.x - 36,
                y: anchor.y - 72,
                width: 72,
                height: 88
            )
            let point = mapView.convert(coordinate, toPointTo: mapView)
            guard !pinHitArea.contains(point) else { return }
        }
        suppressNextMapTap = true
        searchFocused = false
        searchPresented = false
        selectedFavoriteID = nil
        pinPlaceName = nil
        session.pin = coordinate
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            pinSelected = true
            pinExpandedActions = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            suppressNextMapTap = false
        }
    }

    private func hitsInteractiveMarker(at coordinate: CLLocationCoordinate2D) -> Bool {
        guard let mapView else { return false }
        let point = mapView.convert(coordinate, toPointTo: mapView)
        if session.favorites.contains(where: { favorite in
            let markerPoint = mapView.convert(favorite.coordinate, toPointTo: mapView)
            return hypot(markerPoint.x - point.x, markerPoint.y - point.y) <= 36
        }) {
            return true
        }

        if session.targetSelectionMode == .pin,
           let pin = session.pin {
            let markerPoint = mapView.convert(pin, toPointTo: mapView)
            let hitArea = CGRect(
                x: markerPoint.x - 36,
                y: markerPoint.y - 76,
                width: 72,
                height: 92
            )
            if hitArea.contains(point) { return true }
        }

        return false
    }

    private var topChrome: some View {
        StatusBarView(mapDataSourceDetector: mapDataSourceDetector)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
    }

    private var crosshairTarget: some View {
        ZStack {
            Rectangle()
                .frame(width: 30, height: 2)
            Rectangle()
                .frame(width: 2, height: 30)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
        .frame(width: 34, height: 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("搜索地点、地址或坐标", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    searchFocused = false
                    searchTextDirectly()
                }
                .onChange(of: searchText) { value in
                    search.region = searchRegion
                    search.query = value
                }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索内容")
            }
            if searchPresented {
                Button {
                    searchFocused = false
                    searchPresented = false
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("收起搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .locusGlass(.interactive, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.results.prefix(5), id: \.self) { item in
                    Button {
                        select(completion: item)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.body)
                                .foregroundStyle(LocusTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.left")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.3)
                }
            }
        }
        .scrollIndicators(.hidden)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxHeight: 300)
    }

    private var searchHistoryResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Label("搜索历史", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        confirmClearSearchHistory = true
                    } label: {
                        Label("清空", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LocusTheme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(height: 42)

                Divider().opacity(0.3)

                ForEach(session.searchHistory.prefix(20)) { entry in
                    HStack(spacing: 8) {
                        Button {
                            select(history: entry)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.fill")
                                    .foregroundStyle(LocusTheme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if !entry.subtitle.isEmpty {
                                        Text(entry.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            session.removeSearchHistory(entry)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除搜索历史：\(entry.title)")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .frame(minHeight: 54)
                    Divider().opacity(0.3)
                }
            }
        }
        .scrollIndicators(.hidden)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(maxHeight: 300)
    }

    private var rightLowerDynamicControl: some View {
        ZStack(alignment: .bottomTrailing) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .matchedGeometryEffect(id: "rightLowerControl", in: rightLowerControlNamespace)
                .transition(.scale(scale: 0.55, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                ZStack(alignment: .bottomTrailing) {
                    rightLowerControls
                    if session.zoomSliderEnabled {
                        railZoomHandle
                            .offset(
                                x: -(MapChromeLayout.rightColumnWidth - 32) / 2,
                                y: -(MapChromeLayout.rightColumnWidth * 4 + 10)
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .matchedGeometryEffect(id: "rightLowerControl", in: rightLowerControlNamespace)
                .transition(.scale(scale: 0.55, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(
            width: 148,
            height: session.joystickActive ? 148 : MapChromeLayout.rightColumnWidth * 4,
            alignment: .bottomTrailing
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: session.joystickActive)
    }

    private var railZoomHandle: some View {
        EdgeMapZoomGesture(
            onBegan: beginEdgeZoom,
            onChanged: updateEdgeZoom,
            onEnded: endEdgeZoom
        )
        .frame(width: 32, height: MapChromeLayout.rightColumnWidth * 3)
        .overlay {
            VStack(spacing: 8) {
                Image(systemName: "chevron.up")
                Capsule()
                    .fill(Color.primary.opacity(0.45))
                    .frame(width: 3, height: 70)
                Image(systemName: "chevron.down")
            }
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
        .locusGlass(.clear, in: Capsule())
        .accessibilityLabel("地图缩放手势区")
        .accessibilityHint("直接向上滑放大，向下滑缩小")
    }

    private var rightLowerControls: some View {
        VStack(spacing: 0) {
            Button {
                dismissStatusDetails()
                toggleCurrentFavorite()
            } label: {
                Image(systemName: currentPinIsFavorite ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentPinIsFavorite ? Color.yellow : Color.primary)
            .disabled(session.selectedTargetCoordinate == nil)
            .accessibilityLabel(currentPinIsFavorite ? "取消收藏" : "添加收藏")

            Divider()
                .overlay(Color.white.opacity(0.22))
                .frame(width: 32)

            rightRailIconButton("folder.fill") {
                dismissStatusDetails()
                searchFocused = false
                showPlaces = true
            }
            .accessibilityLabel("打开收藏夹")

            Divider()
                .overlay(Color.white.opacity(0.22))
                .frame(width: 32)

            rightRailIconButton("square.3.layers.3d") {
                dismissStatusDetails()
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 2
            }
            .accessibilityLabel("切换地图图层")

            Divider()
                .overlay(Color.white.opacity(0.22))
                .frame(width: 32)

            rightRailIconButton("location.fill") {
                dismissStatusDetails()
                UISelectionFeedbackGenerator().selectionChanged()
                searchFocused = false
                handleLocationButtonTap()
            }
            .accessibilityLabel("回到当前位置；再次轻点回正北")
        }
        .padding(4)
        .frame(width: MapChromeLayout.rightColumnWidth)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
        .foregroundStyle(.primary)
    }

    private func dismissStatusDetails() {
        NotificationCenter.default.post(name: .locusDismissStatusDetails, object: nil)
    }

    private var bottomControlClearance: CGFloat {
        MapChromeLayout.rightRailClearance
    }

    private var routeReadyState: Bool {
        routeCoords.count > 1 && !drawMode && !session.routeActive && !session.routePaused
    }

    private var canAddRouteWaypoint: Bool {
        guard let routeStart else { return false }
        return routeReadyState &&
            !routeIsHandDrawn &&
            !isRouting &&
            routeEnd != nil &&
            ChinaCoordinateTransform.usesMainlandChinaOffset(routeStart)
    }

    private var selectedPlannedRoute: PlannedRoute? {
        guard let selectedRouteOptionID else { return routeOptions.first }
        return routeOptions.first(where: { $0.id == selectedRouteOptionID }) ?? routeOptions.first
    }

    private var selectedRouteColor: Color {
        Color(red: 0.0, green: 0.42, blue: 0.24)
    }

    private var unselectedRouteColor: Color {
        Color(red: 0.39, green: 0.78, blue: 0.55).opacity(0.72)
    }

    private var presentedRouteColor: Color {
        routeIsHandDrawn ? LocusTheme.accentSecondary : LocusTheme.accent
    }

    /// The route overlay style depends on whether alternatives exist:
    /// - No alternatives: the presented route (hand-drawn dashed vs. accent solid).
    /// - With alternatives: the selected option in dark green.
    private var mainRouteColor: Color {
        routeOptions.isEmpty ? presentedRouteColor : selectedRouteColor
    }

    private var mainRouteLineWidth: CGFloat {
        if routeOptions.isEmpty { return routeIsHandDrawn ? 4 : 5 }
        return 6
    }

    private var mainRouteDashed: Bool {
        routeOptions.isEmpty && routeIsHandDrawn
    }

    private var alternativeRouteCoords: [[CLLocationCoordinate2D]] {
        routeOptions
            .filter { $0.id != selectedRouteOptionID }
            .map(\.coordinates)
    }

    private var currentPinIsFavorite: Bool {
        guard let target = session.selectedTargetCoordinate else { return false }
        return session.favorite(at: target) != nil
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let recenterDistance: CLLocationDistance = 750
        let newRegion: MKCoordinateRegion
        if session.isSpoofing, let sim = session.simulated {
            newRegion = MKCoordinateRegion(
                center: sim,
                latitudinalMeters: recenterDistance,
                longitudinalMeters: recenterDistance
            )
        } else if let real = session.realMapCoordinate {
            newRegion = MKCoordinateRegion(
                center: real,
                latitudinalMeters: recenterDistance,
                longitudinalMeters: recenterDistance
            )
        } else {
            newRegion = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                latitudinalMeters: 2000,
                longitudinalMeters: 2000
            )
        }
        animateRegionToken += 1
        region = newRegion
    }

    private func handleLocationButtonTap() {
        let now = Date()
        if let lastLocationButtonTap,
           now.timeIntervalSince(lastLocationButtonTap) <= 2 {
            faceMapNorth()
            self.lastLocationButtonTap = nil
        } else {
            goToCurrentLocation()
            lastLocationButtonTap = now
        }
    }

    private func faceMapNorth() {
        guard let camera = mapView?.camera else {
            goToCurrentLocation()
            return
        }
        animateRegionToken += 1
        region = MKCoordinateRegion(
            center: camera.centerCoordinate,
            span: region.span
        )
    }

    private func beginEdgeZoom() {
        edgeZoomStartRegion = region
    }

    private func updateEdgeZoom(_ verticalTranslation: CGFloat) {
        guard let start = edgeZoomStartRegion else { return }
        let scale = pow(2, Double(verticalTranslation / 120))
        let latitudeDelta = min(120, max(0.0005, start.span.latitudeDelta * scale))
        let longitudeDelta = min(360, max(0.0005, start.span.longitudeDelta * scale))
        region = MKCoordinateRegion(
            center: start.center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }

    private func endEdgeZoom() {
        edgeZoomStartRegion = nil
    }

    private func rightRailIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func toggleCurrentFavorite() {
        guard let target = session.selectedTargetCoordinate else { return }
        let name = session.suggestedFavoriteName(for: target, fallback: pinPlaceName)
        let result = session.toggleFavorite(name: name, coordinate: target)
        pinSelected = false
        pinExpandedActions = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if result.added, let favorite = session.favorite(at: target) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                favoriteRenameSuggestion = favorite
            }
        } else if let suggestion = favoriteRenameSuggestion,
                  session.favorite(at: suggestion.coordinate) == nil {
            favoriteRenameSuggestion = nil
        }
        showFavoriteToast(result.added ? "已收藏：\(result.name)" : "已取消收藏：\(result.name)")
    }

    private func selectFavorite(_ favorite: SavedPlace) {
        suppressNextMapTap = true
        pinSelected = false
        pinPlaceName = session.favoriteDisplayName(favorite)
        searchNamedCoordinate = favorite.coordinate
        session.pin = favorite.coordinate
        if session.targetSelectionMode == .crosshair {
            session.crosshairCoordinate = favorite.coordinate
            let span = region.span
            region = MKCoordinateRegion(center: favorite.coordinate, span: span)
        }
        session.teleport(to: favorite.coordinate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            suppressNextMapTap = false
        }
    }

    private func removeFavoriteFromMap(_ favorite: SavedPlace) {
        suppressNextMapTap = true
        selectedFavoriteID = nil
        pinSelected = false
        pinExpandedActions = false
        if favoriteRenameSuggestion?.id == favorite.id {
            favoriteRenameSuggestion = nil
        }
        session.removeFavorite(favorite)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showFavoriteToast("已删除收藏：\(session.favoriteDisplayName(favorite))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            suppressNextMapTap = false
        }
    }

    private func buildRouteToCurrentTarget() {
        guard !session.routeActive, !session.routePaused else {
            session.lastError = "请先结束当前轨迹，再生成新轨迹。"
            return
        }
        guard let target = session.selectedTargetCoordinate else {
            session.lastError = session.targetSelectionMode == .crosshair
                ? "尚未取得准星位置，请先移动地图。"
                : "请先在地图上放置图钉。"
            return
        }
        guard let current = currentRouteLocation else {
            session.lastError = "尚未取得当前定位，请稍后重试。"
            return
        }
        routeStart = current
        routeEnd = target
        routeWaypoints.removeAll()
        closePinActions()
        showFavoriteToast(session.targetSelectionMode == .crosshair
                          ? "正在生成前往准星的道路轨迹"
                          : "正在生成前往图钉的道路轨迹")
        buildRoadRoute()
    }

    private func closePinActions() {
        suppressNextMapTap = true
        withAnimation(.easeOut(duration: 0.15)) {
            pinSelected = false
            pinExpandedActions = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            suppressNextMapTap = false
        }
    }

    private var currentRouteLocation: CLLocationCoordinate2D? {
        // Same fallback chain as the ios16 build: simulated → real GPS → pin.
        session.simulated ?? session.realMapCoordinate ?? session.pin
    }

    private var simulatedCoordinateKey: String {
        guard let coordinate = session.simulated else { return "none" }
        return String(format: "%.7f,%.7f", coordinate.latitude, coordinate.longitude)
    }

    private func followSimulatedLocationIfNeeded() {
        guard session.autoFollowRoute,
              session.routeActive,
              let simulated = session.simulated else { return }
        let span = region.span
        region = MKCoordinateRegion(center: simulated, span: span)
    }

    private func showFavoriteToast(_ message: String) {
        favoriteToastTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            favoriteToast = message
        }
        favoriteToastTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.18)) {
                favoriteToast = nil
            }
        }
    }

    private var searchRegion: MKCoordinateRegion {
        let center = session.selectedTargetCoordinate ?? session.simulated ?? session.realMapCoordinate ??
            CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
        return MKCoordinateRegion(center: center, latitudinalMeters: 80_000, longitudinalMeters: 80_000)
    }

    private func searchTextDirectly() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = searchRegion
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                await MainActor.run {
                    applySearchResult(
                        title: item.name ?? query,
                        subtitle: item.placemark.title ?? "",
                        coordinate: coord
                    )
                }
            } else {
                await MainActor.run { session.lastError = "没有找到匹配的地点。" }
            }
        }
    }

    private func select(completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                let title = item.name ?? completion.title
                await MainActor.run {
                    applySearchResult(
                        title: title,
                        subtitle: completion.subtitle,
                        coordinate: coord
                    )
                }
            }
        }
    }

    private func select(history entry: SearchHistoryEntry) {
        applySearchResult(title: entry.title, subtitle: entry.subtitle, coordinate: entry.coordinate)
    }

    private func applySearchResult(
        title: String,
        subtitle: String,
        coordinate: CLLocationCoordinate2D
    ) {
        pinPlaceName = title
        searchNamedCoordinate = coordinate
        if session.targetSelectionMode == .pin {
            session.pin = coordinate
        } else {
            session.crosshairCoordinate = coordinate
        }
        animateRegionToken += 1
        region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1200,
            longitudinalMeters: 1200
        )
        searchText = ""
        search.query = ""
        searchFocused = false
        searchPresented = false
        session.pushNamedRecent(name: title, coordinate: coordinate)
        session.recordSearch(title: title, subtitle: subtitle, coordinate: coordinate)
    }

    private func buildRoadRoute() {
        guard !isRouting else { return }
        guard let start = routeStart, let end = routeEnd else {
            session.lastError = "请设置路线起点和终点。"
            return
        }
        isRouting = true
        Task {
            do {
                let options = try await RouteBuilder.roadRoutes(
                    from: start,
                    to: end,
                    via: routeWaypoints,
                    mode: session.travelMode,
                    requestsAlternatives: ChinaCoordinateTransform.usesMainlandChinaOffset(start)
                )
                await MainActor.run {
                    drawnPath.removeAll()
                    drawnRouteStart = nil
                    drawnRouteEnd = nil
                    drawMode = false
                    routeIsHandDrawn = false
                    routeOptions = options
                    selectedRouteOptionID = options.first?.id
                    routeCoords = options.first?.coordinates ?? []
                    isRouting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showFavoriteToast("道路轨迹已生成")
                }
            } catch {
                await MainActor.run {
                    isRouting = false
                    session.lastError = error.localizedDescription
                }
            }
        }
    }

    private func playRoute() {
        if let selectedPlannedRoute {
            routeOptions = [selectedPlannedRoute]
            selectedRouteOptionID = selectedPlannedRoute.id
            routeCoords = selectedPlannedRoute.coordinates
        }
        let path = routeCoords
        guard path.count >= 2 else {
            session.lastError = "请先规划、手绘或导入一条轨迹。"
            return
        }
        showRouteSheet = false
        session.followRoute(path)
    }

    private func runGeneratedRoute() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if session.canResumeRoute {
            session.resumeRoute()
        } else {
            playRoute()
        }
    }

    private func deleteGeneratedRoute() {
        withAnimation(.easeOut(duration: 0.2)) {
            clearRoutePresentation()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showFavoriteToast("轨迹已删除")
    }

    private func clearRoutePresentation() {
        session.discardRoute()
        routeCoords.removeAll()
        routeOptions.removeAll()
        selectedRouteOptionID = nil
        routeWaypoints.removeAll()
        drawnPath.removeAll()
        drawnRouteStart = nil
        drawnRouteEnd = nil
        drawMode = false
        routeIsHandDrawn = false
        routeStart = nil
        routeEnd = nil
    }

    private func beginDrawingRoute() {
        session.discardRoute()
        routeCoords.removeAll()
        routeOptions.removeAll()
        selectedRouteOptionID = nil
        routeWaypoints.removeAll()
        drawnPath.removeAll()
        drawnRouteStart = nil
        drawnRouteEnd = nil
        routeIsHandDrawn = false
        routeStart = nil
        routeEnd = nil
        drawMode = true
        closePinActions()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFavoriteToast("已开始手绘轨迹")
    }

    private func cancelDrawingRoute() {
        guard drawMode else { return }
        drawnPath.removeAll()
        drawnRouteStart = nil
        drawnRouteEnd = nil
        drawMode = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        showFavoriteToast("已取消手绘")
    }

    private func undoDrawingPoint() {
        guard drawMode, !drawnPath.isEmpty else { return }
        drawnPath.removeLast()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func saveDrawingRoute() {
        guard drawMode, drawnPath.count > 1,
              let start = drawnPath.first,
              let end = drawnPath.last else {
            session.lastError = "请至少绘制两个点后再保存。"
            return
        }
        drawnRouteStart = start
        drawnRouteEnd = end
        routeIsHandDrawn = true
        routeOptions.removeAll()
        selectedRouteOptionID = nil
        routeWaypoints.removeAll()
        routeCoords = RouteBuilder.sample(coordinates: drawnPath, every: 10)
        drawnPath.removeAll()
        drawMode = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showFavoriteToast("手绘轨迹已保存")
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
            drawnPath.removeAll()
            drawnRouteStart = nil
            drawnRouteEnd = nil
            drawMode = false
            routeIsHandDrawn = false
            routeOptions.removeAll()
            selectedRouteOptionID = nil
            routeWaypoints.removeAll()
            routeCoords = RouteBuilder.sample(coordinates: coords, every: 10)
            if let first = coords.first {
                session.pin = first
                region = MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private func exportGPX() {
        let path = routeCoords.isEmpty ? drawnPath : routeCoords
        guard !path.isEmpty else {
            session.lastError = "当前没有可导出的轨迹。"
            return
        }
        let gpx = GPXCodec.export(path)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Route.gpx")
        do {
            try gpx.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private struct EdgeMapZoomGesture: View {
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    @State private var isActive = false
    @State private var lastFeedbackStep = 0

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(zoomGesture)
    }

    private var zoomGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                activateIfNeeded()
                onChanged(value.translation.height)
                let feedbackStep = Int((value.translation.height / 72).rounded(.towardZero))
                if feedbackStep != lastFeedbackStep {
                    lastFeedbackStep = feedbackStep
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { _ in
                guard isActive else { return }
                isActive = false
                lastFeedbackStep = 0
                onEnded()
            }
    }

    private func activateIfNeeded() {
        guard !isActive else { return }
        isActive = true
        lastFeedbackStep = 0
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onBegan()
    }
}

private struct FavoriteMapMarker: View {
    var selected: Bool
    var onSelect: () -> Void
    var onLongPress: () -> Void
    var onRemove: () -> Void
    @State private var isPressing = false
    @State private var longPressActivated = false
    @State private var longPressTask: Task<Void, Never>?
    @State private var pressStarted = false
    @State private var pressCancelled = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Button {
                guard !longPressActivated, !pressCancelled else { return }
                onSelect()
            } label: {
                Image(systemName: "star.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .frame(width: 44, height: 44)
                    .scaleEffect(isPressing ? 0.92 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(favoritePressGesture)

            if selected {
                Button(action: onRemove) {
                    Label("删除收藏", systemImage: "trash.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LocusTheme.danger)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
                .locusGlass(.regular, in: Capsule())
                .contentShape(Capsule())
                .fixedSize()
                .offset(y: -46)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
        }
        // The delete button remains inside this frame, so the map cannot receive
        // it as a background tap and create a replacement pin.
        .frame(width: 160, height: 92, alignment: .bottom)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selected)
        .animation(.easeOut(duration: 0.12), value: isPressing)
        .onDisappear {
            longPressTask?.cancel()
            longPressTask = nil
        }
    }

    private var favoritePressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pressStarted {
                    pressStarted = true
                    pressCancelled = false
                    isPressing = true
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    longPressTask?.cancel()
                    longPressTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.5))
                        guard !Task.isCancelled, pressStarted, !longPressActivated else { return }
                        longPressActivated = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onLongPress()
                    }
                }

                let movement = max(abs(value.translation.width), abs(value.translation.height))
                if movement > 12, !longPressActivated {
                    longPressTask?.cancel()
                    longPressTask = nil
                    pressCancelled = true
                    isPressing = false
                }
            }
            .onEnded { _ in
                longPressTask?.cancel()
                longPressTask = nil
                pressStarted = false
                isPressing = false
                if longPressActivated {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        longPressActivated = false
                        pressCancelled = false
                    }
                } else if pressCancelled {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        pressCancelled = false
                    }
                }
            }
    }
}

private struct RouteEndpointMarker: View {
    let color: Color
    let systemImage: String

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

private struct RouteWaypointMarker: View {
    let number: Int

    var body: some View {
        ZStack {
            Image(systemName: "mappin.circle.fill")
                .font(.title.weight(.semibold))
                .foregroundStyle(.blue)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .offset(y: -2)
        }
        .frame(width: 38, height: 44)
        .accessibilityLabel("途经点 \(number)")
    }
}

// MARK: - MKMapView bridge (iOS 16)

/// UIViewRepresentable wrapping MKMapView so the map works on iOS 16, where the
/// SwiftUI Map / MapReader / MapCameraPosition API is unavailable.
struct LocusMapView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var mapType: MKMapType
    /// Bump to ease the next region change over 0.35s (locate button).
    var animateRegionToken: Int
    var simulated: CLLocationCoordinate2D?
    var routeCoords: [CLLocationCoordinate2D]
    var routeColor: Color
    var routeLineWidth: CGFloat
    var routeDashed: Bool
    var alternativeRouteCoords: [[CLLocationCoordinate2D]]
    var drawnPath: [CLLocationCoordinate2D]
    var onMapViewCreated: (MKMapView) -> Void
    var onMapTap: (CLLocationCoordinate2D) -> Void
    var onMapLongPress: (CLLocationCoordinate2D) -> Void
    var onRegionSettled: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)
        coordinator.onRegionSettled = onRegionSettled
        return coordinator
    }

    func makeUIView(context: Context) -> MKMapView {
        // Create with a real frame (not .zero): on iOS 16, VectorKit's Metal
        // canvas initializes against the creation geometry and never recovers
        // from a zero frame, leaving a black map. Using the screen bounds gives
        // the renderer a valid canvas from the start.
        let mapView = MKMapView(frame: UIScreen.main.bounds)
        // Style is driven via mapView.mapType, NOT preferredConfiguration:
        // switching preferredConfiguration on iOS 16 corrupts VectorKit's
        // renderer ("Tracking renderables for inactive registry", SO 77818532)
        // and leaves a black map. mapType is soft-deprecated but works reliably
        // on iOS 16 and is what Geranium-style apps use.
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        mapView.showsScale = false
        // Do NOT call setRegion here: at this point the view still has a zero
        // frame (it has not been laid out yet), and applying a region against
        // empty geometry can leave the map renderer in a broken black state.
        // The initial region is applied in updateUIView once bounds are valid.

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.mapTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        mapView.addGestureRecognizer(tap)

        // Long-press: waypoint insertion (mainland China) / expanded pin actions.
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.mapLongPressed(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        mapView.addGestureRecognizer(longPress)

        // MKMapView's internal recognizers (double-tap-to-zoom etc.) cancel touches by
        // default, which swallows the first tap on SwiftUI buttons overlaid on the map.
        // Disabling cancellation lets the button's touch sequence survive arbitration.
        Self.disableTouchCancellation(in: mapView)

        // Gate every recognizer (ours and MapKit's, on the map view itself) so
        // they only see touches that land inside the map's own view hierarchy.
        // SwiftUI buttons overlaid on the map live outside that hierarchy, so
        // their taps no longer enter the map's gesture arbitration. Recursing
        // into MapKit's internal subviews breaks its pan/zoom coordination, so
        // only the map view's own recognizers are gated.
        let gate = MapTouchGate()
        context.coordinator.touchGate = gate
        for recognizer in mapView.gestureRecognizers ?? [] {
            recognizer.delegate = gate
            // The double-tap-to-zoom recognizer is the one that swallows the
            // first tap on overlay buttons: it waits to see whether a second
            // tap follows. Disable it outright — two-finger pinch, the zoom
            // slider and the joystick cover zooming.
            if let tap = recognizer as? UITapGestureRecognizer,
               tap.numberOfTapsRequired == 2 {
                tap.isEnabled = false
            }
        }
        tap.delegate = gate
        longPress.delegate = gate

        onMapViewCreated(mapView)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Only touch the map type when the requested one changed; re-assigning
        // it on every update churns MapKit's VectorKit renderer and can blank
        // the map (iOS 16.x).
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }

        // Apply the initial region only once the view has a real frame.
        if !context.coordinator.didSetInitialRegion, mapView.bounds.size != .zero {
            context.coordinator.didSetInitialRegion = true
            mapView.setRegion(region, animated: false)
            context.coordinator.lastRegion = region
        }

        // Apply programmatic region changes only; never fight the user's pan.
        if let last = context.coordinator.lastRegion, Self.regionDiffers(last, region) {
            if context.coordinator.animateRegionToken != animateRegionToken {
                UIView.animate(withDuration: 0.35, delay: 0, options: .curveEaseInOut) {
                    mapView.setRegion(region, animated: false)
                }
            } else {
                mapView.setRegion(region, animated: false)
            }
            context.coordinator.lastRegion = region
        }
        context.coordinator.animateRegionToken = animateRegionToken

        // Spoofed-location marker.
        if let simulated {
            if let annotation = context.coordinator.spoofAnnotation {
                annotation.coordinate = simulated
            } else {
                let annotation = MKPointAnnotation()
                annotation.coordinate = simulated
                mapView.addAnnotation(annotation)
                context.coordinator.spoofAnnotation = annotation
            }
        } else if let annotation = context.coordinator.spoofAnnotation {
            mapView.removeAnnotation(annotation)
            context.coordinator.spoofAnnotation = nil
        }

        // Rebuilding overlays is expensive (hundreds of points, add/remove
        // churn on the renderer), and updateUIView fires on every body change
        // (status updates, region settles...). Only rebuild when the route
        // data actually changed; otherwise taps feel laggy while the main
        // thread churns through polyline construction.
        let routeKey = Self.coordinatesKey(routeCoords)
        let alternativesKey = alternativeRouteCoords.map(Self.coordinatesKey)
        let drawnKey = Self.coordinatesKey(drawnPath)
        if routeKey != context.coordinator.routeKey
            || alternativesKey != context.coordinator.alternativesKey
            || drawnKey != context.coordinator.drawnKey {
            context.coordinator.routeKey = routeKey
            context.coordinator.alternativesKey = alternativesKey
            context.coordinator.drawnKey = drawnKey

            // Selected / presented route polyline.
            if routeCoords.count > 1 {
                if let overlay = context.coordinator.routeOverlay { mapView.removeOverlay(overlay) }
                let polyline = MKPolyline(coordinates: routeCoords, count: routeCoords.count)
                // Assign before addOverlay: MapKit may call rendererFor synchronously
                // from within addOverlay, and rendererFor dispatches on identity.
                context.coordinator.routeOverlay = polyline
                mapView.addOverlay(polyline)
            } else if let overlay = context.coordinator.routeOverlay {
                mapView.removeOverlay(overlay)
                context.coordinator.routeOverlay = nil
            }

            // Alternative route polylines (unselected options).
            for overlay in context.coordinator.alternativeOverlays {
                mapView.removeOverlay(overlay)
            }
            context.coordinator.alternativeOverlays.removeAll()
            for coords in alternativeRouteCoords where coords.count > 1 {
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                context.coordinator.alternativeOverlays.append(polyline)
                mapView.addOverlay(polyline)
            }

            // Drawn path polyline (dashed).
            if drawnPath.count > 1 {
                if let overlay = context.coordinator.drawnOverlay { mapView.removeOverlay(overlay) }
                let polyline = MKPolyline(coordinates: drawnPath, count: drawnPath.count)
                context.coordinator.drawnOverlay = polyline
                mapView.addOverlay(polyline)
            } else if let overlay = context.coordinator.drawnOverlay {
                mapView.removeOverlay(overlay)
                context.coordinator.drawnOverlay = nil
            }
        }
    }

    private static func coordinatesKey(_ coords: [CLLocationCoordinate2D]) -> String {
        guard let first = coords.first, let last = coords.last else { return "\(coords.count)" }
        return "\(coords.count):\(first.latitude),\(first.longitude)-\(last.latitude),\(last.longitude)"
    }

    private static func disableTouchCancellation(in view: UIView) {
        view.gestureRecognizers?.forEach {
            $0.cancelsTouchesInView = false
            // MKMapView's double-tap-to-zoom recognizer delays touchesEnded
            // while it waits to see whether a second tap follows. Buttons
            // overlaid on the map (route run/delete, route choices) then need
            // several taps before SwiftUI sees a clean touch sequence.
            $0.delaysTouchesBegan = false
            $0.delaysTouchesEnded = false
        }
        view.subviews.forEach { disableTouchCancellation(in: $0) }
    }

    /// Lets map gesture recognizers see only touches that land inside the map's
    /// own view hierarchy. SwiftUI controls overlaid on the map live outside
    /// that hierarchy, so their taps never enter the map's gesture arbitration
    /// and never get swallowed by double-tap-to-zoom / pan / pinch.
    final class MapTouchGate: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let mapView = gestureRecognizer.view else { return false }
            guard let view = touch.view else { return false }
            return view === mapView || view.isDescendant(of: mapView)
        }
    }

    private static func regionDiffers(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
        lhs.center.latitude != rhs.center.latitude
            || lhs.center.longitude != rhs.center.longitude
            || lhs.span.latitudeDelta != rhs.span.latitudeDelta
            || lhs.span.longitudeDelta != rhs.span.longitudeDelta
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: LocusMapView
        var lastRegion: MKCoordinateRegion?
        var didSetInitialRegion = false
        var animateRegionToken = 0
        var spoofAnnotation: MKPointAnnotation?
        var routeOverlay: MKPolyline?
        var alternativeOverlays: [MKPolyline] = []
        var drawnOverlay: MKPolyline?
        var routeKey: String?
        var alternativesKey: [String]?
        var drawnKey: String?
        var touchGate: MapTouchGate?
        var onRegionSettled: (() -> Void)?

        init(_ parent: LocusMapView) {
            self.parent = parent
        }

        @objc func mapTapped(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            parent.onMapTap(coordinate)
        }

        @objc func mapLongPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let mapView = recognizer.view as? MKMapView else { return }
            let coordinate = mapView.convert(recognizer.location(in: mapView), toCoordinateFrom: mapView)
            parent.onMapLongPress(coordinate)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            lastRegion = mapView.region
            // During the initial frame, MKMapView reports its default region
            // (e.g. the whole country view) before the app's initial region has
            // been applied; writing that back to the @Binding would clobber the
            // initial region and leave the map anywhere but where the app asked.
            // Defer callbacks until the initial region is applied.
            guard didSetInitialRegion else { return }
            parent.region = mapView.region
            onRegionSettled?()
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let spoof = spoofAnnotation, annotation === spoof else { return nil }
            let identifier = "locus.spoof"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.annotation = annotation
            view.isEnabled = false
            view.canShowCallout = false

            if view.subviews.isEmpty {
                let outer = UIView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
                outer.layer.cornerRadius = 22
                outer.backgroundColor = UIColor(LocusTheme.accent).withAlphaComponent(0.25)

                let inner = UIView(frame: CGRect(x: 15, y: 15, width: 14, height: 14))
                inner.layer.cornerRadius = 7
                inner.backgroundColor = UIColor(LocusTheme.accent)
                inner.layer.borderWidth = 2
                inner.layer.borderColor = UIColor.white.cgColor

                outer.addSubview(inner)
                view.addSubview(outer)
            }
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.lineCap = .round
                renderer.lineJoin = .round
                if polyline === routeOverlay {
                    renderer.strokeColor = UIColor(parent.routeColor)
                    renderer.lineWidth = parent.routeLineWidth
                    if parent.routeDashed {
                        renderer.lineDashPattern = [6, 4]
                    }
                } else if alternativeOverlays.contains(where: { $0 === polyline }) {
                    renderer.strokeColor = UIColor(
                        Color(red: 0.39, green: 0.78, blue: 0.55)
                            .opacity(0.72)
                    )
                    renderer.lineWidth = 4
                } else if polyline === drawnOverlay {
                    renderer.strokeColor = UIColor(LocusTheme.accentSecondary)
                    renderer.lineWidth = 4
                    renderer.lineDashPattern = [6, 4]
                }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet { completer.queryFragment = query }
    }

    var region: MKCoordinateRegion {
        get { completer.region }
        set { completer.region = newValue }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
