import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showPlaces: Bool
    @Binding var favoriteRenameSuggestion: SavedPlace?
    @Binding var searchPresented: Bool
    @Binding var showRouteSheet: Bool
    @Binding var generatedRouteReady: Bool
    @Binding var drawingRouteActive: Bool
    @Binding var drawingRoutePointCount: Int

    @StateObject private var search = PlaceSearchCompleter()
    @Namespace private var rightLowerControlNamespace
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeIsHandDrawn = false
    @State private var routeCameraRevision: UInt = 0
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var edgeZoomStartRegion: MKCoordinateRegion?
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
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

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
                                    selectFavorite(favorite)
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
                            .accessibilityHint("一秒内松手可切换模拟位置，按住一秒显示删除按钮")
                        }
                    }

                    if let pin = session.pin, session.favorite(at: pin) == nil {
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
                                onBuildRouteToPin: buildRouteToCurrentPin,
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
                    if let sim = session.simulated {
                        Annotation("模拟位置", coordinate: sim) {
                            ZStack {
                                Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                                Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    if routeCoords.count > 1, session.mapStyleIndex == 0 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(
                                presentedRouteColor,
                                style: presentedRouteStrokeStyle
                            )
                    }
                    if drawnPath.count > 1, session.mapStyleIndex == 0 {
                        MapPolyline(coordinates: drawnPath)
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
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
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onMapCameraChange(frequency: .continuous) { _ in
                    guard session.mapStyleIndex != 0,
                          routeCoords.count > 1 || drawnPath.count > 1 else { return }
                    routeCameraRevision &+= 1
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
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
                .overlay {
                    if session.mapStyleIndex != 0 {
                        ZStack {
                            if routeCoords.count > 1 {
                                ScreenFixedRouteOverlay(
                                    coordinates: routeCoords,
                                    proxy: proxy,
                                    cameraRevision: routeCameraRevision,
                                    color: presentedRouteColor,
                                    strokeStyle: presentedRouteStrokeStyle
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
            .background(Color.black.ignoresSafeArea())

            edgeZoomStrip

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
                    if !searchText.isEmpty && !search.results.isEmpty {
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
        .onAppear {
            session.startLocationUpdates()
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
            drawingRouteActive = false
            drawingRoutePointCount = 0
        }
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
                drawMode: drawMode,
                onToggleDrawing: {
                    if !drawMode {
                        beginDrawingRoute()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if drawMode {
            drawnPath.append(coord)
        } else {
            session.pin = coord
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private func placeExpandedPin(at point: CGPoint, proxy: MapProxy) {
        guard !drawMode,
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

    private func mapLongPressGesture(proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if mapPressStartPoint == nil {
                    let startPoint = value.startLocation
                    mapPressStartPoint = startPoint
                    mapLongPressTask?.cancel()
                    mapLongPressTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled,
                              mapPressStartPoint != nil,
                              !mapLongPressActivated else { return }
                        mapLongPressActivated = true
                        dismissStatusDetails()
                        placeExpandedPin(at: startPoint, proxy: proxy)
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
        StatusBarView()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)
    }

    private var edgeZoomStrip: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                EdgeMapZoomGesture(
                    onBegan: beginEdgeZoom,
                    onChanged: updateEdgeZoom,
                    onEnded: endEdgeZoom
                )
                .frame(width: 18)
            }
            .padding(.vertical, 140)
        }
        .allowsHitTesting(!searchPresented)
        .zIndex(1)
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
                rightLowerControls
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
            .disabled(session.pin == nil)
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
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }
            .accessibilityLabel("切换地图图层")

            Divider()
                .overlay(Color.white.opacity(0.22))
                .frame(width: 32)

            rightRailIconButton("location.fill") {
                dismissStatusDetails()
                UISelectionFeedbackGenerator().selectionChanged()
                searchFocused = false
                goToCurrentLocation()
            }
            .accessibilityLabel("回到当前位置")
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

    private var presentedRouteColor: Color {
        routeIsHandDrawn ? LocusTheme.accentSecondary : LocusTheme.accent
    }

    private var presentedRouteStrokeStyle: StrokeStyle {
        routeIsHandDrawn
            ? StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: [6, 4])
            : StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
    }

    private var currentPinIsFavorite: Bool {
        guard let pin = session.pin else { return false }
        return session.favorite(at: pin) != nil
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realMapCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
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

    private func beginEdgeZoom() {
        edgeZoomStartRegion = visibleRegion
    }

    private func updateEdgeZoom(_ verticalTranslation: CGFloat) {
        guard let start = edgeZoomStartRegion else { return }
        let scale = pow(2, Double(verticalTranslation / 180))
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
        guard let pin = session.pin else { return }
        let name = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
        let result = session.toggleFavorite(name: name, coordinate: pin)
        pinSelected = false
        pinExpandedActions = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if result.added, let favorite = session.favorite(at: pin) {
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
        session.pin = favorite.coordinate
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

    private func buildRouteToCurrentPin() {
        guard let pin = session.pin else { return }
        guard let current = currentRouteLocation else {
            session.lastError = "尚未取得当前定位，请稍后重试。"
            return
        }
        routeStart = current
        routeEnd = pin
        closePinActions()
        showFavoriteToast("正在生成前往图钉的道路轨迹")
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
        let center = session.simulated ?? session.pin ?? session.realMapCoordinate ??
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
                    session.pin = coord
                    pinPlaceName = item.name ?? query
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    searchPresented = false
                    session.pushNamedRecent(name: item.name ?? query, coordinate: coord)
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
                    session.pin = coord
                    pinPlaceName = title
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    searchPresented = false
                    session.pushNamedRecent(name: title, coordinate: coord)
                }
            }
        }
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
                let coords = try await RouteBuilder.roadRoute(from: start, to: end, mode: session.travelMode)
                await MainActor.run {
                    drawnPath.removeAll()
                    drawnRouteStart = nil
                    drawnRouteEnd = nil
                    drawMode = false
                    routeIsHandDrawn = false
                    routeCoords = coords
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
            .accessibilityHidden(true)
    }

    private var zoomGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    activateIfNeeded()
                case .second(true, let drag):
                    activateIfNeeded()
                    guard let drag else { return }
                    onChanged(drag.translation.height)
                    let feedbackStep = Int((drag.translation.height / 72).rounded(.towardZero))
                    if feedbackStep != lastFeedbackStep {
                        lastFeedbackStep = feedbackStep
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                default:
                    break
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
                    longPressTask?.cancel()
                    longPressTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
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
