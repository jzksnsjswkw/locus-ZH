import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupDocument: LocusBackupDocument?
    @State private var pendingBackup: LocusBackup?
    @State private var backupNotice: String?
    @State private var confirmClearSearchHistory = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "已安装 RPPairing 配对文件" : "未安装配对文件")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("在此 iPhone 上配对", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("导入 RPPairing 文件…") { showImporter = true }
                    Button("从剪贴板粘贴 RPPairing") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("删除配对文件", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("开发者配对")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "在 iOS 27 上可使用“在此 iPhone 上配对”，无需电脑。Locus 会广播可配对主机；请前往“设置”›“隐私与安全性”›“开发者模式”›“与主机配对”，确认 6 位代码。较旧的 iOS 版本需要导入由 idevice_pair 生成的 RPPairing 文件（不是 SideStore 的 lockdown .mobiledevicepairing 文件）。LiveContainer：请为 Locus 启用“修复文件选择器（Fix File Picker）”，或使用“粘贴”/“共享”→ LiveContainer → Locus。"
                         : "请导入由 idevice_pair 生成的 RPPairing 文件（不是 SideStore 的 lockdown .mobiledevicepairing 文件）。如果文件选择器失效（LiveContainer 中较常见），请为此应用启用“修复文件选择器（Fix File Picker）”，将文件共享到 LiveContainer → Locus，或复制 plist 内容后使用“粘贴”。")
                }

                Section("地图与交互") {
                    Picker("定位点选择方式", selection: $session.targetSelectionMode) {
                        ForEach(TargetSelectionMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.icon).tag(mode)
                        }
                    }

                    Picker("地图样式", selection: $session.mapStyleIndex) {
                        Text("标准").tag(0)
                        Text("卫星混合").tag(1)
                    }

                    Picker("外观", selection: $session.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle("街景", isOn: $session.lookAroundEnabled)
                    Toggle("地图缩放滑条", isOn: $session.zoomSliderEnabled)
                    Toggle("轨迹运行时自动跟随", isOn: $session.autoFollowRoute)
                    Toggle("启动时恢复上次地图视角", isOn: $session.restoreLastMapView)
                } footer: {
                    Text("街景仅在 Apple 提供 Look Around 的地区可用。地图缩放滑条默认关闭；开启后可直接上下拖动。")
                }

                Section {
                    Toggle("保存搜索历史", isOn: $session.searchHistoryEnabled)
                    if !session.searchHistory.isEmpty {
                        Button("清空搜索历史", role: .destructive) {
                            confirmClearSearchHistory = true
                        }
                    }
                    Button {
                        backupDocument = LocusBackupDocument(backup: session.makeBackup())
                        showBackupExporter = true
                    } label: {
                        Label("导出 Locus 备份", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showBackupImporter = true
                    } label: {
                        Label("导入 Locus 备份", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("搜索与数据")
                } footer: {
                    Text("备份包含收藏、搜索历史和安全的界面设置，不包含 RPPairing、隧道 IP、正在运行的轨迹或设备连接状态。")
                }

                Section {
                    TextField("设备隧道 IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("状态") {
                        Text(LocalDevVPN.isConnected ? "已连接" : "未连接")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("保存隧道 IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "打开 LocalDevVPN" : "获取 LocalDevVPN（App Store）",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("隧道")
                } footer: {
                    Text("开始模拟定位前请连接 LocalDevVPN。默认隧道 IP 为 10.7.0.1。首次模拟定位请使用 Wi‑Fi，之后可继续通过蜂窝网络运行。")
                }

                Section("隐私") {
                    Text("所有数据均在设备端处理。收藏与搜索历史保存在 UserDefaults 中；无分析统计、无需账户，也不会上传任何内容。街景开启后，MapKit 会向 Apple 请求当前地图中心附近的公开街景场景。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("定位引擎", value: "idevice DVT 定位模拟")
                    Link(destination: URL(string: "https://github.com/Bellaboy/locus-ZH")!) {
                        LabeledContent("项目主页", value: "Bellaboy/locus-ZH")
                    }
                    LabeledContent("原始项目", value: "ChrisMack32/Locus")
                    Text("Locus 是采用 MIT 许可证的免费开源软件。定位注入使用采用 MIT 许可证的 idevice FFI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus，名词——地点。源自拉丁语，意为你所在之处。")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .fileExporter(
                isPresented: $showBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "Locus-Backup"
            ) { result in
                if case .failure(let error) = result {
                    backupNotice = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showBackupImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importBackup(result)
            }
            .confirmationDialog(
                "导入 Locus 备份",
                isPresented: Binding(
                    get: { pendingBackup != nil },
                    set: { if !$0 { pendingBackup = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("合并收藏与历史，并应用设置") {
                    guard let backup = pendingBackup else { return }
                    do {
                        try session.applyBackup(backup)
                        backupNotice = "备份导入完成。"
                    } catch {
                        backupNotice = error.localizedDescription
                    }
                    pendingBackup = nil
                }
                Button("取消", role: .cancel) { pendingBackup = nil }
            } message: {
                if let backup = pendingBackup {
                    Text("将导入 \(backup.favorites.count) 个收藏和 \(backup.searchHistory.count) 条搜索历史；本机同坐标收藏优先保留。")
                }
            }
            .alert("Locus 备份", isPresented: Binding(
                get: { backupNotice != nil },
                set: { if !$0 { backupNotice = nil } }
            )) {
                Button("确定", role: .cancel) { backupNotice = nil }
            } message: {
                Text(backupNotice ?? "")
            }
            .alert("清空搜索历史", isPresented: $confirmClearSearchHistory) {
                Button("清空", role: .destructive) { session.clearSearchHistory() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作无法撤销。")
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            pendingBackup = try decoder.decode(LocusBackup.self, from: data).validated()
        } catch {
            backupNotice = error.localizedDescription
        }
    }
}

struct PlacesView: View {
    private struct FavoriteGroup: Identifiable {
        let id: String
        let places: [SavedPlace]
    }

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                if session.favorites.isEmpty {
                    Section("收藏地点") {
                        Text("在地图上选择图钉并点击星标即可收藏。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(groupedFavorites) { group in
                        Section(group.id) {
                            ForEach(group.places) { place in
                                favoriteButton(place)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            session.removeFavorite(place)
                                        } label: {
                                            Label("删除", systemImage: "trash.fill")
                                        }
                                        Button {
                                            placeToRename = place
                                            renameText = session.favoriteDisplayName(place)
                                        } label: {
                                            Label("重命名", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }
                    }
                }

            }
            .navigationTitle("地点")
            .task {
                await session.backfillFavoriteCountries()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("重命名收藏", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) {
                    placeToRename = nil
                }
                Button("保存") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("设置一个方便以后识别的名称。")
            }
        }
    }

    private var groupedFavorites: [FavoriteGroup] {
        let grouped = Dictionary(grouping: session.favorites) { place in
            let country = place.countryName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let city = place.cityName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [country, city]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else { return nil }
                    return value
                }
                .reduce(into: [String]()) { result, value in
                    if result.last != value { result.append(value) }
                }
            return parts.isEmpty ? "未知地区" : parts.joined(separator: " ")
        }
        return grouped.keys
            .sorted { lhs, rhs in
                if lhs == "未知地区" { return false }
                if rhs == "未知地区" { return true }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { FavoriteGroup(id: $0, places: grouped[$0] ?? []) }
    }

    private func favoriteButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            Text(session.favoriteDisplayName(place))
                .foregroundStyle(.primary)
        }
    }

}
