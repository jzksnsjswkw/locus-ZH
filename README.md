# Locus

免费开源的 iPhone 虚拟定位工具。点一下地图、搜索一个地点，或者规划一条路线——Locus 通过苹果的私有 **CLSimulationManager** 接口把模拟坐标注入系统定位服务 `locationd`，让地图 App 和其他应用看到的是你设定的位置（而不是那种室外 GPS 一刷新就覆盖掉的 Wi‑Fi 定位）。

支持 **iOS 15.0 及以上**。用 **TrollStore** 安装即可——不需要配对文件、不需要开发者通道、不需要电脑、也不需要开启开发者模式。

<p align="center">
  <img src="docs/screenshots/map.png" alt="Locus 地图定位界面" width="180" />
  <img src="docs/screenshots/spoofing.png" alt="Locus 3D 模拟定位" width="180" />
  <img src="docs/screenshots/joystick.png" alt="Locus 摇杆控制" width="180" />
  <img src="docs/screenshots/route.png" alt="Locus 地图路线" width="180" />
</p>

## 功能

- 一键传送（地图打点或搜索地点）
- 实时摇杆——走路 / 跑步 / 骑行 / 驾车，带轻微速度变化
- 步行 / 驾车路线规划，沿真实道路与步道（MapKit）
- 可配置定位更新间隔与随机抖动，移动节奏更接近真实 GPS
- 手绘路径，支持导入 / 导出 GPX
- 后台保持在线 + 实时状态栏 + 掉落提醒
- 收藏与最近记录
- 首次使用引导
- 完全离线运行——无统计、无上传

## 安装

完整步骤见 [SETUP.md](SETUP.md)。可以直接从 [Releases](https://github.com/jzksnsjswkw/locus-ZH/releases) 下载预编译的 `.tipa` 文件，或按下方说明自行编译。

应用标识（Bundle ID）：`com.chrismack.locus`

**前提：** 必须用 **TrollStore** 安装 Locus。重签名时应用需要保留 `com.apple.locationd.simulation` 权限，而 TrollStore 是唯一能保留任意权限的侧载工具。如果用普通签名方式安装，模拟定位接口会静默失效。

## 使用教程

### 快速开始（一键传送）

1. 打开 Locus，地图会自动显示你的当前位置
2. 选一个目标位置，两种方式任选：
   - **地图打点**：点一下地图任意位置放置图钉
   - **搜索**：点右下角的搜索按钮，输入地名或经纬度
3. 选好位置后，点击底部控制栏的开始按钮——系统定位立刻切换到所选位置

### 轨迹模拟（沿规划路线移动）

1. 打开设置，把**定位点选择方式**改为**屏幕准星**
2. 回到地图，屏幕中央会出现一个准星——**移动地图，让准星对准你想去的终点**（准星位置就是轨迹的终点位）
3. 点击"生成轨迹"，Locus 会从当前位置到准星位置规划一条路线
4. **开始模拟之前**，可以用**单指长按地图**在任意位置添加**途经点**，路线会自动调整经过这些位置；不需要途经点也可以直接开始
5. 如果有多个备选方案，可以在路线 1 / 路线 2 之间切换，然后点击"运行"开始模拟——模拟位置会沿着路线移动

### 摇杆模式

点击右侧的摇杆按钮，用屏幕上的摇杆手动控制模拟位置的移动，支持走路 / 跑步 / 骑行 / 驾车四种速度档位。

### 手绘路径与 GPX

- **手绘路径**：切换到手绘模式，直接在地图上画出你想要的路线
- **GPX**：可以导入 `.gpx` 文件作为路线，也可以把当前路线导出为 GPX 文件

### 随机抖动

在设置中开启"位置抖动"并设置抖动半径（0.1–20 米），模拟位置会在半径范围内轻微随机跳动，更接近真实 GPS 的表现。

### 更新间隔

在设置中可以调整移动时推送模拟坐标的频率——**定位更新间隔**（0.1–10 秒，步进 100 毫秒）。更新间隔只影响采样密度，不影响行进速度；开启"更新间隔随机抖动"后，每次更新的实际间隔会随机微调（幅度不会超过更新间隔），让移动节奏更自然。

## 原理

Locus 调用苹果私有的 `CLSimulationManager`（CoreLocation）——与 Geranium、Andromeda、TrollTools、locsim 等工具使用的是同一个接口。它把模拟坐标注入系统级的 `locationd`：

- 不需要配对文件、开发者通道、LocalDevVPN、开发者模式，也不需要电脑。
- `com.apple.locationd.simulation` 权限是访问入口（由 TrollStore 的 fake-root 重签名保留）。
- 模拟是**系统级**的，并且 **Locus 被关闭后依然生效**——它存在于 `locationd` 中。当 `locationd` 重启或设备重启后才会清除。
- 开始传送后，Locus 会保持一个轻量的后台会话，让定位在应用打开期间保持新鲜。

### 关于 Pokémon GO 与类似游戏

Locus 与苹果自家模拟器用相同方式模拟定位：告诉 iOS"你现在在这里"，其他应用从系统中读取该位置。只信任系统 GPS 的应用（苹果地图等）会跟随。

**Pokémon GO 不一样。** 它自带定位校验，经常拒绝开发者 / 模拟 GPS（例如提示"无法检测到位置"）。这是该方法的预期结果，不是 Locus 的 bug，此应用也没有针对它的受支持修复方案。

像 **iPogo** 这类工具（以及 SpooferPro 等修改版客户端）原理不同：它们是**修改过的 Pokémon GO 客户端**，而不是系统级虚拟定位。功能内置在那个被修改的游戏客户端里，而不是通过 iOS 把坐标提供给每个应用。因此那些工具看起来"能在 Pokémon GO 里用"，而 Locus 能正常驱动地图却被 Pokémon GO 的校验拦截。

Locus 是用于系统级传送的工具，不是 Pokémon GO 客户端，也不是反作弊绕过工具。

## 编译

从源码编译需要一个 Apple 开发者账号（免费或付费均可）用于代码签名。发布的 `.tipa` **不需要**——直接用 TrollStore 侧载即可。

1. 需要的话先安装 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
2. 在 `project.yml` 中设置你的 **Team ID**（`DEVELOPMENT_TEAM`），或者在生成工程后在 Xcode → Signing & Capabilities 中选择你的团队。
3. 生成并打开工程：

```bash
xcodegen generate
open Locus.xcodeproj
```

或者用命令行编译（把 Team ID 替换成你账号里的）：

```bash
xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -destination 'generic/platform=iOS' DEVELOPMENT_TEAM=YOUR_TEAM_ID build
```

### 打包成 TrollStore 安装包（.tipa）

免签名编译、用 `ldid -S` 携带权限假签名，再打包成 `.tipa`：

```bash
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  CODE_SIGNING_ALLOWED=NO -derivedDataPath build build
APP=build/Build/Products/Release-iphoneos/Locus.app
ldid -SLocus/Resources/Locus.entitlements "$APP/Locus"
cd build/Build/Products/Release-iphoneos && zip -r Locus.tipa Payload
```

然后用 TrollStore 安装 `Locus.tipa`。

## 声明

- 本项目基于 [ChrisMack32/Locus](https://github.com/ChrisMack32/Locus) 二次开发，原项目遵循 MIT 许可证。
- 本项目所有代码由 DeepSeek V4 Flash Free OpenCode Zen 生成，开发 Agent 为 OpenCode。
- 本软件仅供学习研究使用，请在下载后 **24 小时内删除**，请勿用于商业用途或从事任何违法违规活动。

## 许可证

MIT。Locus 是独立开源项目，与 Mirage / Wapixel 无关。