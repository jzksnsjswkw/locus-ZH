import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showNameEasterEgg = false
    @State private var showBackupExporter = false
    @State private var showBackupImporter = false
    @State private var backupDocument: LocusBackupDocument?
    @State private var pendingBackup: LocusBackup?
    @State private var backupNotice: String?
    @State private var confirmClearSearchHistory = false

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                mapInteractionSection
                    .locusSheetRows()

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
                    Text("备份包含收藏、搜索历史和安全的界面设置，不包含正在运行的轨迹或设备连接状态。")
                }
                .locusSheetRows()

                privacySection
                    .locusSheetRows()

                Section("关于") {
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("定位引擎", value: "CLSimulationManager（TrollStore）")
                    Link(destination: URL(string: "https://github.com/Bellaboy/locus-ZH")!) {
                        LabeledContent("项目主页", value: "Bellaboy/locus-ZH")
                    }
                    LabeledContent("原始项目", value: "ChrisMack32/Locus")
                    Text("Locus 是采用 MIT 许可证的免费开源软件。定位注入使用 Apple 私有 CoreLocation 模拟 API（com.apple.locationd.simulation 权限）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .locusSheetRows()

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
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
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
        }
    }

    private var mapInteractionSection: some View {
        Section {
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

            Toggle("地图缩放滑条", isOn: $session.zoomSliderEnabled)
            Toggle("轨迹运行时自动跟随", isOn: $session.autoFollowRoute)
            Toggle("启动时恢复上次地图视角", isOn: $session.restoreLastMapView)

            Toggle("模拟位置随机抖动", isOn: $session.locationJitterEnabled)
            if session.locationJitterEnabled {
                Stepper(value: $session.locationJitterRadius, in: 1...20, step: 1) {
                    LabeledContent("抖动半径") {
                        Text("\(Int(session.locationJitterRadius)) 米")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("地图与交互")
        } footer: {
            Text("位置抖动让轨迹更接近真实 GPS 行为；半径越大抖动越明显。")
        }
    }

    private var privacySection: some View {
        Section("隐私") {
            Text("所有数据均在设备端处理。收藏与搜索历史保存在 UserDefaults 中；无分析统计、无需账户，也不会上传任何内容。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                    .locusSheetRows()
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
                        .locusSheetRows()
                    }
                }

            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("收藏夹")
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
            session.teleport(to: place.coordinate)
            dismiss()
        } label: {
            Text(session.favoriteDisplayName(place))
                .foregroundStyle(.primary)
        }
    }

}
