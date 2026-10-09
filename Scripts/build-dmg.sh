#!/bin/bash
# 文件职责：以 Release 配置构建 Developer ID 签名的 GearMac.app，并打包为 build/GearMac-<版本>.dmg。
# 分层：脚本（发布打包）；签名身份从本机钥匙串动态解析，缺少时直接失败并指向 docs/signing.md。
#
# 用法：./Scripts/build-dmg.sh [version]
#
# 说明：分发用的 DMG 使用 Developer ID Application 证书签名（Team ID 锚定钥匙串/TCC 授权，
# 且是公证的前提）；codesign 保持默认 secure timestamp（公证必需，勿加 --timestamp=none）。
# 本脚本只负责构建与打包；公证（notarytool submit + stapler）见 docs/release.md。
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
# 固定使用 Xcode 工具链，避免落到 CommandLineTools 上。
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# 分发签名身份：本机钥匙串中的第一张 Developer ID Application 证书。
IDENTITY="$(security find-identity -v -p codesigning | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')"
# DerivedData 输出目录。
DERIVED="build/DerivedData"

# 先确认钥匙串里存在 Developer ID 签名身份，否则 xcodebuild 会以难以理解的方式失败。
if [ -z "$IDENTITY" ]; then
    echo "✗ No 'Developer ID Application' identity found — see docs/signing.md." >&2
    exit 1
fi
echo "▸ Signing identity: $IDENTITY"

echo "▸ Building signed GearMac.app (Release)…"
xcodebuild -project GearMac.xcodeproj -scheme GearMac -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/GearMac.app"
# 从 Info.plist 读回真实版本号，保证 DMG 文件名与实际产物一致。
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/GearMac-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
# 在临时目录里组织 DMG 内容：应用本体 + /Applications 软链。
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
# 拖拽安装所需的 Applications 快捷方式。
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
# UDZO 即压缩只读格式。
diskutil image create from "$STAGE" --format UDZO --volumeName "GearMac" "$DMG" >/dev/null
rm -rf "$STAGE"

# DMG 本体也用 Developer ID 签名（公证提交 DMG 时要求）。
codesign --sign "$IDENTITY" --timestamp "$DMG"

echo "✓ $DMG"
