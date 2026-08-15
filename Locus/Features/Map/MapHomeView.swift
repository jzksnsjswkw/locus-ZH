import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
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
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var routeWaypoints: [CLLocationCoordinate2D] = []
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeIsHandDrawn = false
    @State private var routeCameraRevision: UInt = 0
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var visibleCamera: MapCamera?
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
    @State private var mapLongPressActivated = false
    @State private var mapLongPressTask: Task<Void, Never>?
    @State private var mapPressStartPoint: CGPoint?
    @State private var favoriteToast: String?
    @State private var favoriteToastTask: Task<Void, Never>?
    @State private var searchNamedCoordinate: CLLocationCoordinate2D?
    @State private var confirmClearSearchHistory = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    var body: some View {
        presentedMap
    }

    private var mapSurface: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    mapContent(proxy: proxy)
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onMapCameraChange(frequency: .continuous) { _ in
                    if session.mapStyleIndex != 0,
                       routeCoords.count > 1 || drawnPath.count > 1 {
                        routeCameraRevision &+= 1
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    visibleCamera = context.camera
                    session.saveMapRegion(context.region)
                    if session.targetSelectionMode == .crosshair {
                        session.crosshairCoordinate = context.region.center
                        if let named = searchNamedCoordinate,
                           CLLocation(latitude: named.latitude, longitude: named.longitude)
                            .distance(from: CLLocation(
                                latitude: context.region.center.latitude,
                                longitude: context.region.center.longitude
                            )) > 15 {
                            pinPlaceName = nil
                            searchNamedCoordinate = nil
                        }
                    }
                }
                .onTapGesture { point in
                    dismissStatusDetails()
                    searchFocused = false
                    searchPresented = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    pinExpandedActions = false
                    selectedFavoriteID = nil
                    placePin(at: point, proxy: proxy)
                }
                .simultaneousGesture(mapLongPressGesture(proxy: proxy))
                .overlay(alignment: .topLeading) {
                    MapDataSourceProbe(detector: mapDataSourceDetector)
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay {
                    if session.mapStyleIndex != 0 {
                        ZStack {
                            if routeOptions.isEmpty, routeCoords.count > 1 {
                                ScreenFixedRouteOverlay(
                                    coordinates: routeCoords,
                                    proxy: proxy,
                                    cameraRevision: routeCameraRevision,
                                    color: presentedRouteColor,
                                    strokeStyle: presentedRouteStrokeStyle
                                )
                            }
                            ForEach(routeOptions.filter { $0.id != selectedRouteOptionID }) { option in
                                ScreenFixedRouteOverlay(
                                    coordinates: option.coordinates,
                                    proxy: proxy,
                                    cameraRevision: routeCameraRevision,
                                    color: unselectedRouteColor,
                                    strokeStyle: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                                )
                            }
                            if let selectedPlannedRoute {
                                ScreenFixedRouteOverlay(
                                    coordinates: selectedPlannedRoute.coordinates,
                                    proxy: proxy,
                                    cameraRevision: routeCameraRevision,
                                    color: selectedRouteColor,
                                    strokeStyle: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                                )
                            }
                            if drawnPath.count > 1 {
                                ScreenFixedRouteOverlay(
                                    coordinates: drawnPath,
                                    proxy: proxy,
                                    cameraRevision: routeCameraRevision,
                                    color: LocusTheme.accentSecondary,
                                    strokeStyle: StrokeStyle(
                                        lineWidth: 4,
                                        lineCap: .round,
                                        lineJoin: .round,
                                        dash: [6, 4]
                                    )
                                )
                            }
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())

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

    private var mapLifecycle: some View {
        mapSurface
        .onAppear {
            session.startLocationUpdates()
            if session.restoreLastMapView, let region = session.savedMapRegion() {
                position = .region(region)
                visibleRegion = region
                if session.targetSelectionMode == .crosshair {
                    session.crosshairCoordinate = region.center
                }
            } else if session.targetSelectionMode == .crosshair,
                      session.crosshairCoordinate == nil {
                session.crosshairCoordinate = session.pin ?? session.simulated ?? session.realMapCoordinate
            }
        }
        .onChange(of: routeReadyState, initial: true) { _, ready in
            generatedRouteReady = ready
        }
        .onChange(of: drawMode, initial: true) { _, active in
            drawingRouteActive = active
        }
        .onChange(of: drawnPath.count, initial: true) { _, count in
            drawingRoutePointCount = count
        }
        .onDisappear {
            mapLongPressTask?.cancel()
            mapLongPressTask = nil
            mapPressStartPoint = nil
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
        .onChange(of: searchPresented) { _, presented in
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
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil {
                pinSelected = false
                pinExpandedActions = false
            }
        }
        .onChange(of: session.status) { _, status in
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
        .onChange(of: session.targetSelectionMode) { _, mode in
            closePinActions()
            if mode == .crosshair {
                session.crosshairCoordinate = visibleRegion?.center ?? session.pin ?? session.simulated ?? session.realMapCoordinate
            }
        }
        .onChange(of: selectedRouteOptionID) { _, selectedID in
            guard let selectedID,
                  let option = routeOptions.first(where: { $0.id == selectedID }) else { return }
            routeCoords = option.coordinates
        }
        .onChange(of: simulatedCoordinateKey) { _, _ in
            followSimulatedLocationIfNeeded()
        }
        .onChange(of: session.locationSummaryRevision) { _, _ in
            mapDataSourceDetector.redetect()
        }
        .onChange(of: scenePhase) { _, phase in
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
            .locusSheetPresentation()
        }
        .alert("清空搜索历史", isPresented: $confirmClearSearchHistory) {
            Button("清空", role: .destructive) { session.clearSearchHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    @MapContentBuilder
    private func mapContent(proxy: MapProxy) -> some MapContent {
        UserAnnotation()
        favoriteAnnotations
        pinAnnotation(proxy: proxy)

        if let sim = session.simulated {
            Annotation("模拟位置", coordinate: sim) {
                ZStack {
                    Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                    Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }

        ForEach(routeWaypoints.indices, id: \.self) { index in
            Annotation("途经点 \(index + 1)", coordinate: routeWaypoints[index], anchor: .bottom) {
                RouteWaypointMarker(number: index + 1)
            }
        }

        routeLineContent

        if let start = drawMode ? drawnPath.first : drawnRouteStart {
            Annotation("手绘轨迹起点", coordinate: start) {
                RouteEndpointMarker(color: .green, systemImage: "play.fill")
            }
        }
        if !drawMode, let end = drawnRouteEnd {
            Annotation("手绘轨迹终点", coordinate: end) {
                RouteEndpointMarker(color: .red, systemImage: "stop.fill")
            }
        }
    }

    @MapContentBuilder
    private var favoriteAnnotations: some MapContent {
        ForEach(session.favorites) { favorite in
            Annotation(
                "",
                coordinate: favorite.coordinate,
                anchor: UnitPoint(x: 0.5, y: 0.76)
            ) {
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
            }
        }
    }

    @MapContentBuilder
    private func pinAnnotation(proxy: MapProxy) -> some MapContent {
        if session.targetSelectionMode == .pin,
           let pin = session.pin,
           session.favorite(at: pin) == nil {
            Annotation("", coordinate: pin, anchor: .bottom) {
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
                        if let coord = proxy.convert(globalPoint, from: .global) {
                            session.pin = coord
                        }
                    },
                    onDragEnded: {
                        isDraggingPin = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            suppressNextMapTap = false
                        }
                    }
                )
            }
        }
    }

    @MapContentBuilder
    private var routeLineContent: some MapContent {
        if session.mapStyleIndex == 0 {
            if routeOptions.isEmpty {
                if routeCoords.count > 1 {
                    MapPolyline(coordinates: routeCoords)
                        .stroke(presentedRouteColor, style: presentedRouteStrokeStyle)
                }
            } else {
                ForEach(routeOptions.filter { $0.id != selectedRouteOptionID }) { option in
                    MapPolyline(coordinates: option.coordinates)
                        .stroke(unselectedRouteColor, lineWidth: 4)
                }
                if let selectedPlannedRoute {
                    MapPolyline(coordinates: selectedPlannedRoute.coordinates)
                        .stroke(selectedRouteColor, lineWidth: 6)
                }
            }
        }

        if drawnPath.count > 1, session.mapStyleIndex == 0 {
            MapPolyline(coordinates: drawnPath)
                .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
        }
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if drawMode {
            drawnPath.append(coord)
        } else if session.targetSelectionMode == .pin {
            session.pin = coord
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private func placeExpandedPin(at point: CGPoint, proxy: MapProxy) {
        guard session.targetSelectionMode == .pin,
              !drawMode,
              !suppressNextMapTap,
              !isDraggingPin else { return }
        if let pin = session.pin,
           let anchor = proxy.convert(pin, to: .local) {
            let pinHitArea = CGRect(
                x: anchor.x - 36,
                y: anchor.y - 72,
                width: 72,
                height: 88
            )
            guard !pinHitArea.contains(point) else { return }
        }
        guard let coordinate = proxy.convert(point, from: .local) else { return }
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

    private func handleMapLongPress(at point: CGPoint, proxy: MapProxy) {
        guard !hitsInteractiveMarker(at: point, proxy: proxy),
              let coordinate = proxy.convert(point, from: .local) else { return }
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
            placeExpandedPin(at: point, proxy: proxy)
        }
    }

    private func hitsInteractiveMarker(at point: CGPoint, proxy: MapProxy) -> Bool {
        if session.favorites.contains(where: { favorite in
            guard let markerPoint = proxy.convert(favorite.coordinate, to: .local) else { return false }
            return hypot(markerPoint.x - point.x, markerPoint.y - point.y) <= 36
        }) {
            return true
        }

        if session.targetSelectionMode == .pin,
           let pin = session.pin,
           let markerPoint = proxy.convert(pin, to: .local) {
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

    private func mapLongPressGesture(proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if mapPressStartPoint == nil {
                    let startPoint = value.startLocation
                    mapPressStartPoint = startPoint
                    mapLongPressTask?.cancel()
                    mapLongPressTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.5))
                        guard !Task.isCancelled,
                              mapPressStartPoint != nil,
                              !mapLongPressActivated else { return }
                        mapLongPressActivated = true
                        dismissStatusDetails()
                        handleMapLongPress(at: startPoint, proxy: proxy)
                    }
                }

                let movement = max(abs(value.translation.width), abs(value.translation.height))
                if movement > 12, !mapLongPressActivated {
                    mapLongPressTask?.cancel()
                    mapLongPressTask = nil
                }
            }
            .onEnded { _ in
                mapLongPressTask?.cancel()
                mapLongPressTask = nil
                mapPressStartPoint = nil
                if mapLongPressActivated {
                    suppressNextMapTap = true
                    mapLongPressActivated = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        suppressNextMapTap = false
                    }
                }
            }
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
                .onChange(of: searchText) { _, value in
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

    private var presentedRouteStrokeStyle: StrokeStyle {
        routeIsHandDrawn
            ? StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [6, 4])
            : StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }

    private var currentPinIsFavorite: Bool {
        guard let target = session.selectedTargetCoordinate else { return false }
        return session.favorite(at: target) != nil
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let recenterDistance: CLLocationDistance = 750
        let currentHeading = visibleCamera?.heading ?? 0
        let currentPitch = visibleCamera?.pitch ?? 0
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .camera(MapCamera(
                    centerCoordinate: sim,
                    distance: recenterDistance,
                    heading: currentHeading,
                    pitch: currentPitch
                ))
            } else if let real = session.realMapCoordinate {
                position = .camera(MapCamera(
                    centerCoordinate: real,
                    distance: recenterDistance,
                    heading: currentHeading,
                    pitch: currentPitch
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
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
        guard let camera = visibleCamera else {
            goToCurrentLocation()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            position = .camera(MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: camera.distance,
                heading: 0,
                pitch: camera.pitch
            ))
        }
    }

    private func beginEdgeZoom() {
        edgeZoomStartRegion = visibleRegion
    }

    private func updateEdgeZoom(_ verticalTranslation: CGFloat) {
        guard let start = edgeZoomStartRegion else { return }
        let scale = pow(2, Double(verticalTranslation / 120))
        let latitudeDelta = min(120, max(0.0005, start.span.latitudeDelta * scale))
        let longitudeDelta = min(360, max(0.0005, start.span.longitudeDelta * scale))
        position = .region(MKCoordinateRegion(
            center: start.center,
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        ))
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
            let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            position = .region(MKCoordinateRegion(center: favorite.coordinate, span: span))
        }
        session.teleport(to: favorite.coordinate, pairing: pairing)
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
        session.simulated ?? session.realMapCoordinate
    }

    private var simulatedCoordinateKey: String {
        guard let coordinate = session.simulated else { return "none" }
        return String(format: "%.7f,%.7f", coordinate.latitude, coordinate.longitude)
    }

    private func followSimulatedLocationIfNeeded() {
        guard session.autoFollowRoute,
              session.routeActive,
              let simulated = session.simulated else { return }
        let span = visibleRegion?.span ?? MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        position = .region(MKCoordinateRegion(center: simulated, span: span))
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
        position = .region(MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: 1200,
            longitudinalMeters: 1200
        ))
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
        session.followRoute(path, pairing: pairing)
    }

    private func runGeneratedRoute() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if session.canResumeRoute {
            session.resumeRoute(pairing: pairing)
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
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
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
        // The delete button remains inside this frame, so Map cannot receive it
        // as a background tap and create a replacement pin.
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

private struct ScreenFixedRouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let proxy: MapProxy
    let cameraRevision: UInt
    let color: Color
    let strokeStyle: StrokeStyle

    var body: some View {
        Canvas { context, _ in
            _ = cameraRevision
            guard coordinates.count > 1 else { return }

            let maximumDisplayPoints = 2_000
            let step = max(1, Int(ceil(Double(coordinates.count - 1) / Double(maximumDisplayPoints - 1))))
            var path = Path()
            var hasCurrentPoint = false
            var lastSampledIndex = -1
            var index = 0

            while index < coordinates.count {
                if let point = proxy.convert(coordinates[index], to: .local) {
                    if hasCurrentPoint {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                        hasCurrentPoint = true
                    }
                } else {
                    hasCurrentPoint = false
                }
                lastSampledIndex = index
                index += step
            }

            let finalIndex = coordinates.count - 1
            if lastSampledIndex != finalIndex,
               let finalPoint = proxy.convert(coordinates[finalIndex], to: .local) {
                if hasCurrentPoint {
                    path.addLine(to: finalPoint)
                } else {
                    path.move(to: finalPoint)
                }
            }

            context.stroke(
                path,
                with: .color(color),
                style: strokeStyle
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
