#!/bin/bash
# 文件职责：对整个项目跑 SwiftLint，并额外跑 Settings 搜索落点检查；传 --fix 会先自动修掉机械性问题。
# 分层：脚本（代码质量门禁）；有 error 即失败，warning 不阻塞。
#
# 用法：./Scripts/lint.sh [--fix]
# 格式由另一个工具负责，且它有自己的注意事项 —— 见 ./Scripts/format.sh。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# swiftlint 不在 PATH 里就直接失败，并给出安装命令。
command -v swiftlint >/dev/null || {
    echo "✗ swiftlint not found. Install it with:  brew install swiftlint" >&2
    exit 2
}

# --fix 只修机械性问题，剩下的交给下面的检查。
[ "${1:-}" = "--fix" ] && swiftlint --fix --quiet

if ! swiftlint lint --quiet; then
    echo
    echo "Lint errors above. Warnings do not block; errors do." >&2
    exit 1
fi
# `Form` 无法被询问它包含什么，所以未被声明的锚点或未被标记的行是一个静默的空操作：搜索
# 结果会导航过去，但什么都不滚动、也不高亮。除此之外没有任何东西能发现这种问题。
if ! node Scripts/check-settings-search.js; then
    exit 1
fi

echo "✓ lint-clean"
