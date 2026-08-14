import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showPlaces: Bool
    @Binding var favoriteRenameSuggestion: SavedPlace?
    @Binding var searchPresented: Bool
    @Binding var showTravelModes: Bool

    @StateObject private var search = PlaceSearchCompleter()
    @Namespace private var rightLowerControlNamespace
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var routeCameraRevision: UInt = 0
    @State private var isRouting = false
    @State private var showRouteSheet = false
    @State private var showGPXImporter = false
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var pinSelected = false
    @State private var pinExpandedActions = false
    @State private var selectedFavoriteID: String?
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
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
                                    showTravelModes = false
                                    selectedFavoriteID = favorite.id
                                    pinSelected = false
                                    pinExpandedActions = false
                                    selectFavorite(favorite)
                                },
                                onRemove: {
                                    removeFavoriteFromMap(favorite)
                                }
                            )
                            .accessibilityLabel(session.favoriteDisplayName(favorite))
                            .accessibilityHint("轻点即可切换模拟位置并显示删除按钮")
                        }
                    }

                    if let pin = session.pin, session.favorite(at: pin) == nil {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                expandedActions: pinExpandedActions,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    showTravelModes = false
                                    suppressNextMapTap = true
                                    selectedFavoriteID = nil
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                        pinExpandedActions = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onShowExpandedActions: {
                                    searchFocused = false
                                    showTravelModes = false
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
                                    showTravelModes = false
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
                                    searchFocused = false
                                    showTravelModes = false
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
                                LocusTheme.accent,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                            )
                    }
                    if drawnPath.count > 1 {
                        MapPolyline(coordinates: drawnPath)
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onMapCameraChange(frequency: .continuous) { _ in
                    if showTravelModes {
                        withAnimation(.easeOut(duration: 0.16)) {
                            showTravelModes = false
                        }
                    }
                    guard session.mapStyleIndex != 0, routeCoords.count > 1 else { return }
                    routeCameraRevision &+= 1
                }
                .onTapGesture { point in
                    searchFocused = false
                    searchPresented = false
                    showTravelModes = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    pinExpandedActions = false
                    selectedFavoriteID = nil
                    placePin(at: point, proxy: proxy)
                }
                .overlay {
                    if routeCoords.count > 1, session.mapStyleIndex != 0 {
                        ScreenFixedRouteOverlay(
                            coordinates: routeCoords,
                            proxy: proxy,
                            cameraRevision: routeCameraRevision
                        )
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())

            topChrome

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

            if routeCoords.count > 1,
               !session.routeActive,
               !session.routePaused,
               !searchPresented {
                VStack {
                    Spacer()
                    routeReadyActions
                        .frame(maxWidth: 250)
                        .padding(.bottom, routeActionBottomClearance)
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: session.routeActive)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: session.routePaused)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: session.joystickActive)
                .animation(.easeOut(duration: 0.18), value: favoriteRenameSuggestion?.id)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
        .onDisappear {
            favoriteToastTask?.cancel()
            favoriteToastTask = nil
            favoriteToast = nil
        }
        .onChange(of: searchPresented) { _, presented in
            if presented {
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
        .onReceive(NotificationCenter.default.publisher(for: .locusImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusDeleteRoute)) { _ in
            deleteGeneratedRoute()
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
                onUseDrawn: {
                    routeCoords = RouteBuilder.sample(coordinates: drawnPath, every: 10)
                    drawnPath.removeAll()
                    drawMode = false
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

    private var topChrome: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusBarView()
            Spacer(minLength: 0)
            mapChromeButtons
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .simultaneousGesture(TapGesture().onEnded {
            showTravelModes = false
        })
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
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
                Button("完成") {
                    searchFocused = false
                    searchPresented = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(search.results.prefix(5), id: \.self) { item in
                    Button {
                        select(completion: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.3)
                }
            }
        }
        .scrollIndicators(.hidden)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxHeight: 280)
    }

    private var mapChromeButtons: some View {
        VStack(spacing: 4) {
            chromeIconButton("square.3.layers.3d") {
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }
            chromeIconButton("point.topleft.down.to.point.bottomright.curvepath") {
                showRouteSheet = true
            }
            chromeIconButton(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle") {
                drawMode.toggle()
                if !drawMode { drawnPath.removeAll() }
            }
            .foregroundStyle(drawMode ? LocusTheme.accentSecondary : .primary)

            chromeIconButton("folder.fill") {
                searchFocused = false
                showPlaces = true
            }
            .accessibilityLabel("打开收藏夹")
        }
        .padding(6)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
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
        .frame(width: 148, height: 148, alignment: .bottomTrailing)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: session.joystickActive)
    }

    private var rightLowerControls: some View {
        VStack(spacing: 0) {
            Button {
                showTravelModes = false
                toggleCurrentFavorite()
            } label: {
                Image(systemName: currentPinIsFavorite ? "star.fill" : "star")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(currentPinIsFavorite ? Color.yellow : Color.primary)
            .disabled(session.pin == nil)
            .accessibilityLabel(currentPinIsFavorite ? "取消收藏" : "添加收藏")

            Divider()
                .frame(width: 30)

            Button {
                searchFocused = false
                showTravelModes = false
                goToCurrentLocation()
            } label: {
                Image(systemName: "location.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到当前位置")
        }
        .padding(4)
        .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .foregroundStyle(.primary)
    }

    private var routeReadyActions: some View {
        HStack(spacing: 6) {
            routeActionButton("删除", systemImage: "trash.fill", color: LocusTheme.danger) {
                deleteGeneratedRoute()
            }
            routeActionButton("运行", systemImage: "play.fill", color: .blue) {
                runGeneratedRoute()
            }
        }
        .padding(5)
        .locusGlass(.regular, in: Capsule())
        .contentShape(Capsule())
    }

    private func routeActionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bottomControlClearance: CGFloat {
        session.routeActive || session.routePaused ? 174 : 96
    }

    private var routeActionBottomClearance: CGFloat {
        bottomControlClearance
            + (session.joystickActive ? 156 : 0)
            + (favoriteRenameSuggestion == nil ? 0 : 52)
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

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            showTravelModes = false
            action()
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
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
        let path = routeCoords.isEmpty ? drawnPath : routeCoords
        guard path.count >= 2 else {
            session.lastError = "请先规划、手绘或导入一条轨迹。"
            return
        }
        showRouteSheet = false
        session.followRoute(path, pairing: pairing)
    }

    private func runGeneratedRoute() {
        showTravelModes = false
        if session.canResumeRoute {
            session.resumeRoute(pairing: pairing)
        } else {
            playRoute()
        }
    }

    private func deleteGeneratedRoute() {
        showTravelModes = false
        session.discardRoute()
        withAnimation(.easeOut(duration: 0.2)) {
            routeCoords.removeAll()
            drawnPath.removeAll()
            routeStart = nil
            routeEnd = nil
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showFavoriteToast("轨迹已删除")
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
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

private struct FavoriteMapMarker: View {
    var selected: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: onSelect) {
                Image(systemName: "star.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.yellow)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
    }
}

private struct ScreenFixedRouteOverlay: View {
    let coordinates: [CLLocationCoordinate2D]
    let proxy: MapProxy
    let cameraRevision: UInt

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
                with: .color(LocusTheme.accent),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
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
