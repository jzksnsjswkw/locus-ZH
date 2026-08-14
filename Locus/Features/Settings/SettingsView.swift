import ActivityKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @AppStorage("locus.liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage(LocusLiveActivityController.statusKey) private var liveActivityStatus = "尚未启动"
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

    private var liveActivityExtensionIncluded: Bool {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL else { return false }
        return FileManager.default.fileExists(
            atPath: plugInsURL.appendingPathComponent("LocusLiveActivity.appex").path
        )
    }

    private var liveActivityDeclaredByMainApp: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool == true
    }

    private var displayedCoordinate: String {
        guard let coordinate = session.simulated ?? session.pin ?? session.realMapCoordinate else {
            return "暂无坐标"
        }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
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

                Section {
                    Toggle(isOn: $liveActivityEnabled) {
                        Label("灵动岛实时状态", systemImage: "waveform.path.ecg.rectangle")
                    }
                    .tint(LocusTheme.accent)

                    LabeledContent(
                        "系统权限",
                        value: ActivityAuthorizationInfo().areActivitiesEnabled ? "已允许" : "未允许"
                    )
                    LabeledContent(
                        "扩展文件",
                        value: liveActivityExtensionIncluded ? "已包含" : "缺失"
                    )
                    LabeledContent(
                        "主应用声明",
                        value: liveActivityDeclaredByMainApp ? "已包含" : "缺失"
                    )
                    LabeledContent("运行状态") {
                        Text(liveActivityStatus)
                            .font(.footnote)
                            .foregroundStyle(liveActivityStatus == "运行中" ? LocusTheme.statusGood : .secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("实时状态")
                } footer: {
                    Text("模拟定位时在灵动岛和锁定屏幕优先显示轨迹已行驶里程与实际运行时间，所在地区作为辅助信息，每 10 秒更新一次。轨迹运行或暂停期间不重新查询地区。独立安装可注册实时活动扩展；标准 LiveContainer 目前不会为客体 App 注册自定义 App Extension，因此即使 IPA 已包含声明与扩展文件，系统仍可能拒绝启动。")
                }

                Section("隐私") {
                    Text("所有数据均在设备端处理。收藏和最近使用记录保存在 UserDefaults 中；无分析统计、无需账户，也不会上传任何内容。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("定位引擎", value: "idevice DVT 定位模拟")
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
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Text(displayedCoordinate)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
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
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
            .onChange(of: liveActivityEnabled) { _, enabled in
                Task {
                    await LocusLiveActivityController.shared.sync(
                        isActive: enabled && session.isSpoofing,
                        status: session.status.label,
                        coordinate: session.simulated,
                        distanceTraveled: session.routeDistanceTraveled,
                        elapsedTime: session.routeElapsedTime,
                        allowRegionLookup: !session.routeActive && !session.routePaused
                    )
                }
            }
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

                Section("最近使用") {
                    if session.recents.isEmpty {
                        Text("使用过的模拟位置会显示在这里。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        recentButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("删除", systemImage: "trash.fill")
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
            guard let name = place.countryName?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return "未知地区" }
            return name
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

    private func recentButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
