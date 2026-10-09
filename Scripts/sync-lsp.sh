#!/bin/bash
# 文件职责：从 xcodebuild 日志重建 SourceKit-LSP 的编译参数数据库（.compile 与 buildServer.json）。
# 分层：脚本（开发环境）；由 VS Code 的 build task 调用，也是一次性的编辑器初始化步骤。
#
# 用法：./Scripts/sync-lsp.sh <xcodebuild-log>
# 详见 docs/development.md。
#
# 不带 `-o` 运行 `xcode-build-server parse` 是刻意的：只有这种写法会同时写出 buildServer.json，
# 而且写成 `kind: manual`。另一条路 `kind: xcode` 完全忽略 .compile，改从 .xcactivitylog 里刮缓存 ——
# 一旦 LogStoreManifest.plist 不再更新，它就会静默冻结，把编辑器钉在旧构建的源文件清单上。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# 必须传入一个存在的日志文件路径。
LOG=${1:-}
if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    echo "usage: $0 <xcodebuild-log>" >&2
    exit 2
fi
# 未安装 xcode-build-server 时安静跳过（不算错误）。
command -v xcode-build-server >/dev/null || { echo "xcode-build-server not installed; skipping." >&2; exit 0; }

# 一次没有编译任何 Swift 的构建不会产生编译命令，解析它会把 .compile 换成空数据库 —— 每个文件
# 都会丢掉参数。这种情况下保留上一份。
backup="${TMPDIR:-/tmp}/gearmac-compile.bak"
[ -f .compile ] && cp .compile "$backup"

xcode-build-server parse < "$LOG" >/dev/null 2>&1

# 结果为空的（或缺 command 字段的）说明日志里没有可用命令，回滚到备份。
if [ ! -s .compile ] || ! grep -q '"command"' .compile 2>/dev/null; then
    if [ -f "$backup" ]; then
        cp "$backup" .compile
        echo "no compile commands in log; kept the previous .compile" >&2
    fi
fi
rm -f "$backup"

# 让 run-tests.sh 把 Tests/ 下各 harness 的命令一并写进 .compile。
./Scripts/run-tests.sh --index
