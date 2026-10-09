#!/bin/bash
# 文件职责：把 Tests/dictation-performance.swift 连同它依赖的已发布源文件编译成临时可执行文件，并运行听写基准。
# 分层：脚本（基准测试）；只读取传入的音频与模型目录，不写入仓库内容。
#
# 用法：./Scripts/benchmark-dictation.sh AUDIO [HELPER_APP] [MODEL_DIRECTORY] [MODEL]
# 默认使用 Debug 构建下的 GearMac-dev 听写 helper，以及开发版 bundle id 对应的模型缓存目录。
set -euo pipefail

# 仓库根目录（以脚本自身位置为基准），用于拼接默认路径。
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# 参数约束：1 个必填（音频），至多 3 个可选。
if (( $# < 1 || $# > 4 )); then
    printf 'Usage: %s AUDIO [HELPER_APP] [MODEL_DIRECTORY] [MODEL]\n' "${0##*/}" >&2
    exit 2
fi
# 默认 helper 应用：Debug 构建产物里的听写 helper。
helper=${2:-"$repo/build/DerivedData/Build/Products/Debug/GearMac-dev.app/Contents/Helpers/GearMac-dev Dictation.app"}
# 默认模型目录：开发版 bundle id 对应的缓存目录。
models=${3:-"$HOME/Library/Caches/com.gearmac.app.dev/Dictation"}
# 编译到临时可执行文件，退出时清理。
binary=$(mktemp /tmp/gearmac-dictation-benchmark.XXXXXX)
trap 'rm -f "$binary"' EXIT
# 把基准入口与它依赖的已发布源文件一起编译，保证测的是真实实现。
swiftc -O -swift-version 6 -target "$(uname -m)-apple-macos26.0" \
    "$repo/Tests/dictation-performance.swift" \
    "$repo/GearMac//Platform/ProcessExit.swift" \
    "$repo/GearMac//Features/Dictation/Model/DictationModel.swift" \
    "$repo/GearMac//Features/Dictation/Service/DictationWire.swift" -o "$binary"
# 第 4 个参数默认 all，表示跑完全部基准项。
"$binary" "$1" "$helper" "$models" "${4:-all}"
