#!/bin/bash
# =============================================================================
# Locus.tipa 打包脚本
# -----------------------------------------------------------------------------
# 用途: 构建 Locus（iOS 16+ 目标）、签名、应用 SDK 版本补丁、打包为 .tipa
# 供 TrollStore 安装。解决 iOS 26 SDK 构建产物在 iOS 16 设备上
# MKMapView 瓦片黑屏的问题（根因: 二进制 LC_BUILD_VERSION.sdk 字段过高,
# 系统框架据此切换渲染路径, iOS 16 的 VectorKit 无法处理）。
#
# 用法:
#   ./build-tipa.sh              # 默认产物: Locus.tipa (含 SDK 补丁)
#   ./build-tipa.sh --no-sdk-patch   # 跳过 vtool SDK 版本补丁
#   ./build-tipa.sh --out NAME.tipa  # 自定义输出文件名
#
# 依赖: Xcode + Command Line Tools (vtool/ldid/plutil)
#       ldid 需预先安装 (brew install ldid 或从 https://github.com/nyanydev/ldid 获取)
# =============================================================================

set -euo pipefail

cd "$(dirname "$0")"

OUT_TIPA="Locus.tipa"
DO_SDK_PATCH=1
SDK_TARGET_VER="18.5"   # 让旧系统认为 app 链接自旧 SDK 的伪装版本
MINOS_VER="16.3"        # 保持与部署目标一致
SDK_NAME="iphoneos26.5" # 构建用 SDK（新 SDK 编译, 运行时伪装旧版本）
ENTITLEMENTS="Locus/Resources/Locus.entitlements"
PBXPROJ="Locus.xcodeproj/project.pbxproj"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sdk-patch) DO_SDK_PATCH=0; shift ;;
    --out) OUT_TIPA="$2"; shift 2 ;;
    --sdk) SDK_NAME="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

echo "==> [1/6] 检查工具链"
for tool in xcodebuild vtool ldid plutil zip codesign; do
  command -v "$tool" >/dev/null 2>&1 || { echo "缺少工具: $tool"; exit 1; }
done
[ -f "$ENTITLEMENTS" ] || { echo "缺少 entitlements: $ENTITLEMENTS"; exit 1; }
[ -f "$PBXPROJ" ] || { echo "缺少工程文件: $PBXPROJ"; exit 1; }

echo "==> [2/6] 构建 (sdk=$SDK_NAME, 免签名)"
xcodebuild -project Locus.xcodeproj -target Locus -sdk "$SDK_NAME" \
  -configuration Release CODE_SIGNING_ALLOWED=NO build 2>&1 \
  | tee /tmp/locus_build.log \
  | grep -E "BUILD (SUCCEEDED|FAILED)|error:" || true

if ! grep -q "BUILD SUCCEEDED" /tmp/locus_build.log; then
  echo "构建失败，见 /tmp/locus_build.log"
  exit 1
fi

APP="build/Release-iphoneos/Locus.app"
BIN="$APP/Locus"
[ -f "$BIN" ] || { echo "找不到构建产物: $BIN"; exit 1; }

if [ "$DO_SDK_PATCH" = "1" ]; then
  echo "==> [3/6] 应用 SDK 版本补丁: sdk 26.5 -> $SDK_TARGET_VER (修复 iOS 16 黑屏地图)"
  vtool -show-build-version "$BIN" 2>/dev/null | grep -E "minos|sdk" || true
  vtool -set-build-version ios "$MINOS_VER" "$SDK_TARGET_VER" -replace -output "$BIN" "$BIN"
  vtool -show-build-version "$BIN" 2>/dev/null | grep -E "minos|sdk" || true
  echo "   (警告: code signature will be invalid 属预期, 下方会重新签名)"
else
  echo "==> [3/6] 跳过 SDK 版本补丁 (--no-sdk-patch)"
fi

echo "==> [4/6] ldid 签名 (嵌入 $ENTITLEMENTS)"
rm -rf "$APP/_CodeSignature"
ldid -S"$ENTITLEMENTS" "$BIN"

echo "==> [5/6] 打包 $OUT_TIPA"
rm -rf /tmp/locus_tipa_pkg
mkdir -p /tmp/locus_tipa_pkg/Payload
cp -R "$APP" /tmp/locus_tipa_pkg/Payload/
rm -f "$OUT_TIPA"
(cd /tmp/locus_tipa_pkg && zip -qry "$OLDPWD/$OUT_TIPA" Payload)
rm -rf /tmp/locus_tipa_pkg build

echo
echo "完成: $OUT_TIPA"
ls -la "$OUT_TIPA"
echo "验证:"
unzip -l "$OUT_TIPA" | head -5
