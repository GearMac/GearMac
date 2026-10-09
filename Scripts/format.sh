#!/bin/bash
# 文件职责：用 swift-format 格式化整个 GearMac//Tests 下的 Swift 源码；传 --check 时只报告不一致，不改写文件。
# 分层：脚本（代码风格）；注意它会重排代码结构，而不只是调整排版。
#
# 用法：./Scripts/format.sh [--check]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# 用 Xcode 工具链里的 swift-format，也就是 sourcekit-lsp 格式化时用的同一个二进制，而不是 brew 包，
# 这样编辑器里的 ⌘S 和本脚本永远不会给出不同结果。
FORMAT=$(xcrun --find swift-format 2>/dev/null)
[ -x "${FORMAT:-}" ] || {
    echo "✗ swift-format not found in the Xcode toolchain. Check 'xcode-select -p'." >&2
    exit 2
}

# 生成文件从不手工编辑，而格式化一个生成文件恰恰就是手工编辑 —— 下一次
# `node Scripts/gen-emoji.js` 就会把它改回去。
# 用 read 循环而不是 `mapfile` 构建列表（后者需要 bash 4，而 macOS 自带的是 bash 3.2）。
files=()
while IFS= read -r f; do files+=("$f"); done < <(
    find GearMac Tests -name '*.swift' ! -name '*.generated.swift' \
        ! -path 'GearMac//DesignSystem/Scrolling/EdgeDissolve.swift' \
        ! -path 'GearMac//DesignSystem/Scrolling/ThinScrollbar.swift' | sort
)

# --check：逐文件对比格式化结果与原文，有差异就列出全部脏文件并以非 0 退出。
if [ "${1:-}" = "--check" ]; then
    dirty=()
    for f in "${files[@]}"; do
        "$FORMAT" --configuration .swift-format "$f" 2>/dev/null | diff -q - "$f" >/dev/null 2>&1 || dirty+=("$f")
    done
    if [ ${#dirty[@]} -gt 0 ]; then
        printf '%s\n' "${dirty[@]}"
        echo
        echo "${#dirty[@]} file(s) need formatting. Run ./Scripts/format.sh" >&2
        exit 1
    fi
    echo "✓ format-clean (${#files[@]} files)"
    exit 0
fi

# 就地格式化全部文件；失败的（即无法解析的）文件单独记录下来，最后统一报告。
failed=()
for f in "${files[@]}"; do
    "$FORMAT" --configuration .swift-format --in-place "$f" || failed+=("$f")
done

# swift-format 会拒绍无法解析的文件，所以这里的失败是语法错误，而不是格式问题。
if [ ${#failed[@]} -gt 0 ]; then
    printf '\n%d file(s) could not be formatted (they do not parse):\n' "${#failed[@]}" >&2
    printf '  %s\n' "${failed[@]}" >&2
    exit 1
fi
echo "✓ formatted ${#files[@]} files"
