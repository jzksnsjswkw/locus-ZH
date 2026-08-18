# 地图黑屏修复 — 最终记录

## 根因（已确认，用户验证成功）

**`platform-application` entitlement 收紧沙箱 → Metal 无法访问 GPU 的 IOKit user client
（AGXDeviceUserClient）→ VectorKit 渲染失败 → 真机地图黑屏。**

### 机制链

1. Locus 使用 `platform-application` + `no-sandbox` + `no-container` entitlements
   （TrollStore 安装所需）。
2. `platform-application` 会使沙箱部分收紧：**IOKit user client 访问需要显式例外**
   （TrollStore README 原文："you need an exception entitlement for every single
   IOKit user client class you want to access"）。
3. MKMapView 的 VectorKit 渲染走 **Metal**，Metal 必须打开 GPU 驱动 user client
   （**AGXDeviceUserClient**）和 IOSurface（**IOSurfaceRootUserClient**）。
4. Locus 之前**没有** `com.apple.security.iokit-user-client-class` → Metal 无法访问
   GPU → 真机黑屏。

### 证据链

| App | iokit-user-client-class | 真机地图 |
|---|---|---|
| Geranium（TrollStore app） | AGXDeviceUserClient + IOSurfaceRootUserClient | ✅ |
| TrollStore 1.3.2 自己 | AGXDeviceUserClient + IOSurfaceRootUserClient（变更日志："Allow TrollStore to access Metal"） | ✅ |
| Locus（修复前） | 无 | ❌ 黑屏 |
| Locus（修复后） | AGXDeviceUserClient + IOSurfaceRootUserClient | ✅ |

### 为什么模拟器正常

模拟器没有真实的 IOKit GPU user client（Metal 走 Mac GPU 翻译/软件渲染），
不受沙箱 IOKit 限制影响。所以同一二进制在 iOS 16.4/26.5 模拟器都正常，
只有真机黑屏——这是"真机特有"问题的关键线索。

## 修复

`Locus/Resources/Locus.entitlements` 添加：

```xml
<key>com.apple.security.iokit-user-client-class</key>
<array>
    <string>AGXDeviceUserClient</string>
    <string>IOSurfaceRootUserClient</string>
</array>
```

## 排除的假设（避免重复排查）

1. **SDK 版本（LC_BUILD_VERSION sdk 26.5）** — 排除。同一二进制在 iOS 16.4
   模拟器正常；vtool 补丁 sdk→18.5 无效。
2. **renderer nudge / preferredConfiguration** — 排除。模拟器正常证明代码路径没问题。
   但 renderer nudge 已删除（它确实触发 iOS 16.7.4 VectorKit 损坏 bug SO 77818532），
   保留删除是正确决定。
3. **越狱 tweak（SSL Kill Switch 3 等）** — 排除。禁用全部 tweak 无效；瓦片由
   geod daemon 下载，app 内 tweak 无法拦截。
4. **MKMapView 零 frame 创建** — 排除。真实 frame 创建已保留（仍是正确做法）。

## 打包

```bash
./build-tipa.sh              # 产物 Locus.tipa（含 SDK 补丁 + 全部 entitlements）
```

脚本自动：临时移除 asset 配置（规避 actool bug）→ 构建 → 恢复 pbxproj →
vtool SDK 补丁（26.5→18.5）→ ldid 签名（嵌入 entitlements）→ 打包 .tipa。

## 遗留说明

- `build-tipa.sh` 的 vtool SDK 补丁（sdk 26.5→18.5）保留：虽然 SDK 版本不是黑屏
  根因，但降低 sdk 字段可减少 iOS 16 上其他潜在兼容问题，无害。
- 若未来用旧版 Xcode（16.x）构建，可 `--no-sdk-patch` 跳过补丁。