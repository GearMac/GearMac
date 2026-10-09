#!/bin/bash
# 文件职责：校验一个已构建的 .app 能通过公证，并且各项权限提示仍会被系统弹出。
# 分层：脚本（发布校验）；只读取签名与 plist，不修改应用包。
#
# 用法：./Scripts/verify-signature.sh <path-to-.app>
set -uo pipefail

APP="${1:?usage: verify-signature.sh <path-to-.app>}"
NAME="$(basename "$APP" .app)"
STATUS=0

# 每个 usage string 在 tccd 弹出提示之前都必须搭配的强化运行时（hardened runtime）权限。
RESOURCE_ENTITLEMENTS=(
    NSAppleEventsUsageDescription=com.apple.security.automation.apple-events
    NSCameraUsageDescription=com.apple.security.device.camera
    NSMicrophoneUsageDescription=com.apple.security.device.audio-input
    NSCalendarsFullAccessUsageDescription=com.apple.security.personal-information.calendars
    NSCalendarsWriteOnlyAccessUsageDescription=com.apple.security.personal-information.calendars
    NSRemindersFullAccessUsageDescription=com.apple.security.personal-information.calendars
    NSContactsUsageDescription=com.apple.security.personal-information.addressbook
    NSLocationWhenInUseUsageDescription=com.apple.security.personal-information.location
    NSPhotoLibraryUsageDescription=com.apple.security.personal-information.photos-library
)

# 记录失败并置非 0 退出码，但不立即退出，以便一次报出全部问题。
fail() {
    echo "✗ $1" >&2
    STATUS=1
}

ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
# 导出应用当前的 entitlements，后面逐项对比。
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null

# helper 由它自己的嵌入阶段签名，运行时标志最容易在这里丢失。
HELPER="$APP/Contents/Helpers/GearMac Dictation.app"
for BIN in "$APP/Contents/MacOS/$NAME" "$APP/Contents/Helpers/ClipboardTextHelper" "$HELPER/Contents/MacOS/GearMac Dictation"; do
    INFO="$(codesign -dv --verbose=2 "$BIN" 2>&1)"
    [[ "$INFO" =~ flags=0x[0-9a-f]+\([^\)]*runtime ]] ||
        fail "${BIN##*/}: hardened runtime not enabled"
done

APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
HELPER_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HELPER/Contents/Info.plist")"
[ "$HELPER_ID" = "$APP_ID.dictation" ] || fail "Dictation helper has an incorrect bundle identifier"
# helper 的签名与 bundle identifier 必须一致，否则公证与权限提示都会出问题。
HELPER_SIGNATURE="$(codesign -dv "$HELPER" 2>&1)"
grep -Fxq "Identifier=$HELPER_ID" <<< "$HELPER_SIGNATURE" ||
    fail "Dictation helper's signature and bundle identifier disagree"

codesign --verify --deep --strict "$APP" || fail "$NAME.app: the seal does not verify"

# Xcode 只在 Debug 下注入它；公证会拒绍任何仍携带它的构建。
/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ENTITLEMENTS" &>/dev/null &&
    fail "$NAME.app: get-task-allow is present"

# 缺失时运行时毫无提示：请求会在几毫秒内直接按拒绝返回，根本不会询问用户。
for PAIR in "${RESOURCE_ENTITLEMENTS[@]}"; do
    USAGE="${PAIR%%=*}" ENTITLEMENT="${PAIR#*=}"
    /usr/libexec/PlistBuddy -c "Print :$USAGE" "$APP/Contents/Info.plist" &>/dev/null || continue
    [ "$(/usr/libexec/PlistBuddy -c "Print :$ENTITLEMENT" "$ENTITLEMENTS" 2>/dev/null)" = true ] ||
        fail "$NAME.app: $USAGE is declared but $ENTITLEMENT is not"
done

if [ "$STATUS" -eq 0 ]; then
    echo "✓ $NAME.app is notarizable and its prompts are entitled"
fi
exit "$STATUS"
