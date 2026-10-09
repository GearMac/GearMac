#!/bin/bash
# 文件职责：把 GitHub 自动生成的 release notes 拼装为两份正文：发布页用的 body.md 与 Discord 用的短版。
# 分层：脚本（发布流程）；依赖 gh CLI 与若干必填环境变量，缺一即失败。
#
# 用法：./Scripts/release-notes.sh <body.md> <discord.md>
# changelog 放在安装标记（MARKER）之上；应用内的更新窗口只显示这一半。详见 docs/release.md。
set -euo pipefail

BODY_OUT="${1:?usage: release-notes.sh <body.md> <discord.md>}"
DISCORD_OUT="${2:?usage: release-notes.sh <body.md> <discord.md>}"

REPO="${REPO:-GearMac/GearMac}"
CHANNEL="${CHANNEL:?CHANNEL is required (beta|stable)}"
TAG="${TAG:?TAG is required, e.g. v0.9.13-beta.61}"
SHA="${SHA:-$(git rev-parse HEAD)}"
VERSION="${VERSION:-${TAG#v}}"
DISPLAY_NAME="${DISPLAY_NAME:-GearMac}"
BUNDLE_ID="${BUNDLE_ID:-com.gearmac.app}"
CASK="${CASK:-gearmac}"

# 这一行以下的内容只给下载页看；应用内的更新窗口在这里截断。
MARKER="<!-- gearmac:install -->"
# Discord 单个组件上限 4000 字符，而且一堆要点全塞进去还不如只给一点。
DISCORD_BUDGET=1200
DISCORD_BULLETS=15

# beta 与 stable 的 tag 在 main 上交错出现 —— 同一个 commit 会同时带两者 —— 所以「上一个发布」
# 只有按 channel 分别判断才是对的。
if [ "$CHANNEL" = "stable" ]; then
    CHANNEL_FILTER='test("-beta\\.") | not'
else
    CHANNEL_FILTER='test("-beta\\.")'
fi
PREVIOUS="$(gh release list --repo "$REPO" --limit 200 --json tagName,isDraft --jq \
    "[.[] | select(.isDraft | not) | .tagName
      | select(. != \"${TAG}\") | select(${CHANNEL_FILTER})] | first // empty")"

# 此时 tag 还不存在 —— 本脚本在 `gh release create` 创建它之前运行。
NOTES_ARGS=(-f "tag_name=${TAG}" -f "target_commitish=${SHA}")
if [ -n "$PREVIOUS" ]; then NOTES_ARGS+=(-f "previous_tag_name=${PREVIOUS}"); fi
echo "▸ Generating notes for ${TAG}${PREVIOUS:+ since ${PREVIOUS}}"
GENERATED="$(gh api "repos/${REPO}/releases/generate-notes" "${NOTES_ARGS[@]}" --jq .body)"

COMPARE_URL="$(printf '%s\n' "$GENERATED" | sed -n 's|^\*\*Full Changelog\*\*: \(.*\)$|\1|p' | tail -n1)"

# 裸的 `#304` 在网页上仍会自动链接，而且能塞进 460pt 宽的更新窗口；完整 URL 两点都做不到。
CHANGELOG="$(printf '%s\n' "$GENERATED" | sed -E \
    -e '/^\*\*Full Changelog\*\*:/d' \
    -e "s|https://github\.com/${REPO}/pull/([0-9]+)|#\1|g")"
[ -n "$(printf '%s' "$CHANGELOG" | tr -d '[:space:]')" ] || CHANGELOG="Maintenance and internal changes."

{
    printf '%s\n\n' "$CHANGELOG"
    printf '%s\n\n' "$MARKER"
    printf '**Channel:** %s · **Version:** %s · **Bundle ID:** `%s`\n' "$CHANNEL" "$VERSION" "$BUNDLE_ID"
    printf 'Built from %s.' "$SHA"
    if [ -n "$COMPARE_URL" ]; then printf ' [Full changelog](%s)' "$COMPARE_URL"; fi
    printf '\n\n'
    printf '%s\n' "**Recommended:** install via Homebrew — it clears the quarantine flag automatically on every install and update, so there's nothing to run by hand:"
    printf '```sh\nbrew trust --tap GearMac/homebrew-gearmac\nbrew install --cask GearMac/homebrew-gearmac/%s\n```\n' "$CASK"
    # 稳定版 DMG 只有 arm64；macOS 26 是最后一个能在 Intel 上启动的版本。
    if [ "$CHANNEL" = "stable" ]; then
        printf '%s\n' "On an **Intel** Mac, install \`GearMac/homebrew-gearmac/gearmac-universal\` instead — same app, built with both slices."
    fi
    printf '%s\n' "This build is self-signed. If you download the DMG directly instead of using Homebrew, macOS will refuse to open it until you clear the quarantine flag once:"
    printf '```sh\nxattr -dr com.apple.quarantine "/Applications/%s.app"\n```\n' "$DISPLAY_NAME"
} > "$BODY_OUT"

printf '%s\n' "$CHANGELOG" | awk -v budget="$DISCORD_BUDGET" -v bullets="$DISCORD_BULLETS" '
    { line = $0 }
    /^[*-] / { seen++ }
    { used += length(line) + 1 }
    used > budget || seen > bullets { print "…and more — see the release page."; exit }
    { print line }
' > "$DISCORD_OUT"

echo "✓ ${BODY_OUT}"
