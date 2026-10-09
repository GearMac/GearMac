#!/bin/bash
# 文件职责：测试套件主入口，为 Tests/ 下每个 harness 组织编译命令、并行派发、执行并汇总结果。
# 分层：脚本（测试 harness 驱动）；没有 XCTest target，每个 harness 自己编译它守护的已发布源文件。
#
# 没有 XCTest target：每个 harness 会编译它守护的已发布源文件，所以某个 harness 编译不过，说明有决策从
# 纯层泄漏出去。详见 docs/testing.md。
#
# 绝不要用 `&&` 连接「编译」与「运行」：`set -e` 不会因 AND-OR 列表里非最后一项失败而退出，
# 这正是 CI 在一个自 phase 10 起就没编译过的 harness 上仍报告成功的原因。
#
# 用法：./Scripts/run-tests.sh [--index | <harness-name>]

set -uo pipefail

# 用绝对路径：worker 在 cd 之后会重新进入本脚本，此时相对 $0 解析不了。
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

# 编译产物与中间状态文件（队列、日志、失败标记）都放在这里。
BIN="${TMPDIR:-/tmp}/gearmac-harness"
mkdir -p "$BIN"

# `--exec` 是 worker 那一半：xargs 会为队列里每个 harness 重新进入这里一次。
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    # 标记本 harness 正在运行，退出时清掉标记与计时文件。
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    # 记录失败并返回 0，不中断 xargs；失败汇总交给父进程。
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    # 只输出真实耗时（秒）。
    TIMEFORMAT=%1R
    # 编译本 harness：$opt 决定优化级别，$@ 是它依赖的源文件；耗时由 $compiled 带回。
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" GearMac/Localization/*.swift "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    # 在后台运行，并把耗时写到 .time；下面轮询等待，以便超时后强杀。
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS 没有 `timeout`，所以 worker 自己轮询；卡住的 harness 必须判失败，而不是拖垮整个套件。
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((GEARMAC_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$GEARMAC_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${GEARMAC_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    # 被信号杀死（状态码 > 128）、或断言失败，都记为 FAIL。
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

# 每次运行都重建队列，并清掉上一轮的失败与运行中标记。
QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
# 只跑指定的单个 harness（若有）。
only="${1:-}"

# `--index` 会把每个 harness 的编译命令并入 .compile，而不实际运行任何东西。
# xcodebuild 从不编译 harness，没有这一步，编辑器里 Tests/ 下的任何东西都无法解析。
# 下面的源文件清单是唯一的一份，这也是它放在这里而不是独立脚本里的原因。
emit_db=0
# 索引模式下临时收集的 harness 条目，最后合并进 .compile。
DB="${TMPDIR:-/tmp}/gearmac-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run [slow] [-O] [index] <name> <source...> —— 把 harness 加入队列。`slow` 让它在第一波就派发；
# `index` 为「手工编译而非由本套件编译」的 harness 声明编辑器 flag。
run() {
    # 默认 -Onone（编译最快），pri=1 为普通优先级。
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    # 指定了 only 且不匹配时直接跳过，不占名额。
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # 全程使用绝对路径：sourcekit-lsp 自己解析命令，不会把 `directory` 应用到相对参数上，
    # 所以那里写相对路径会静默地得不到索引。
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" GearMac/Localization/*.swift "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # 声明 `Tests/` 下的每个文件：harness 以及和它一起编译的辅助文件。已发布的源文件保持不声明，
        # 否则它会拿到这条简短命令而不是应用那条完整命令，而 `.compile` 是后写覆盖 —— 不过应用
        # 从不编译 `Tests/` 里的任何东西。
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs 按空白切分队列，因此任何 harness 源文件路径都不能含空格。
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=GearMac/Features/Launcher/Model
# 以下逐个声明 harness：名称、优化级别、优先级，及其依赖的已发布源文件。
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift $L/LauncherSuggestions.swift
run file-search-test       $L/SearchRelevance.swift \
                           GearMac/Features/FileSearch/Model/*.swift
run file-search-session-test GearMac/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             GearMac/Features/FileSearch/Model/*.swift \
                             GearMac/Features/FileSearch/Service/*.swift
run menu-search-test       $L/SearchRelevance.swift \
                           GearMac/Features/MenuSearch/Model/*.swift \
                           GearMac/Features/MenuSearch/Service/*.swift
run window-switch-test     $L/SearchRelevance.swift \
                           GearMac/Features/WindowSwitcher/Model/*.swift
run index file-search-performance GearMac/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           GearMac/Features/FileSearch/Model/*.swift \
                           GearMac/Features/FileSearch/Service/FileSearchService.swift
run ranking-test           $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/LauncherMatch.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift
run app-name-test          GearMac/Platform/AppDisplayName.swift \
                           GearMac/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run launcher-file-test     $L/LauncherFileFormat.swift \
                           GearMac/Features/Settings/Model/SettingsFileJSON.swift
run launcher-settings-file-test \
                           $L/LauncherFileFormat.swift $L/CommandID.swift $L/CommandCatalog.swift \
                           GearMac/Features/Launcher/Service/LauncherSettingsFile.swift \
                           GearMac/Features/Launcher/Service/AliasStore.swift \
                           GearMac/Features/Launcher/Service/VisibilityStore.swift \
                           GearMac/Features/Settings/SettingsTab.swift \
                           GearMac/Features/Settings/Model/*.swift \
                           GearMac/Features/HotKeys/Service/HotKeySettingsFile.swift \
                           GearMac/Features/HotKeys/Service/KeyShortcut.swift \
                           GearMac/Features/HotKeys/Model/HotKeyAction.swift \
                           GearMac/Features/HotKeys/Model/HotKeyBinding.swift \
                           GearMac/Features/HotKeys/Model/HotKeySpelling.swift \
                           GearMac/Features/HotKeys/Model/DoubleTapModifier.swift \
                           GearMac/Features/HotKeys/Model/ModifierKey.swift \
                           GearMac/Features/HotKeys/Model/HyperKey.swift \
                           GearMac/Platform/ASCIIKeyboardLayout.swift \
                           GearMac/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/SystemActions/Model/SystemAction.swift \
                           GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/Snippets/Model/Snippet.swift
run apple-shortcut-test    GearMac/Features/AppleShortcuts/Model/*.swift
run calc-test              GearMac/Features/Calculator/Model/*.swift
run index calc-performance GearMac/Features/Calculator/Model/*.swift
run calendar-test          GearMac/Features/Calendar/Model/*.swift
run clipboard-test         GearMac/Features/Clipboard/Model/ClipboardStore.swift \
                           GearMac/Features/Clipboard/Model/ClipTag.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFilter.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFileKind.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorFormat.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift
# `Q` 是拖拽负载构建链接时用的那个 URL 识别器，避免再写第二个。
Q=GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift
run clipboard-search-test  GearMac/Features/Clipboard/Model/*.swift $Q
run paste-sequence-test    GearMac/Features/Clipboard/Model/*.swift $Q
run clipboard-text-test    GearMac/Features/Clipboard/Model/*.swift $Q \
                           GearMac/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           GearMac/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           GearMac/Features/Clipboard/Service/ClipboardTextWorker.swift \
                           GearMac/Platform/ProcessExit.swift
run pasteboard-test        GearMac/Platform/PasteboardFiles.swift \
                           GearMac/Features/Clipboard/Model/ClipboardStore.swift \
                           GearMac/Features/Clipboard/Model/ClipTag.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFilter.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFileKind.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorFormat.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift \
                           GearMac/Features/Clipboard/Service/ClipboardManager.swift \
                           GearMac/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           GearMac/Platform/PasteboardFiles.swift \
                           GearMac/Features/Clipboard/Model/ClipboardStore.swift \
                           GearMac/Features/Clipboard/Model/ClipTag.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFilter.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFileKind.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorFormat.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift \
                           GearMac/Features/Clipboard/Service/ClipboardManager.swift
run emoji-test             GearMac/Features/Emoji/Model/EmojiCatalog.swift \
                           GearMac/Features/Emoji/Model/EmojiGridGeometry.swift \
                           GearMac/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      GearMac/Features/Emoji/Model/EmojiCatalog.swift \
                           GearMac/Features/Emoji/Model/EmojiData.generated.swift \
                           GearMac/Features/Emoji/Service/EmojiIndex.swift \
                           GearMac/Features/Emoji/Service/FrequentEmojiStore.swift \
                           GearMac/Features/Emoji/Service/PinnedEmojiStore.swift \
                           GearMac/Features/Launcher/Model/SearchRelevance.swift \
                           GearMac/Platform/AppPaths.swift GearMac/Platform/Memo.swift
run index emoji-search-performance \
                           GearMac/Features/Emoji/Model/EmojiCatalog.swift \
                           GearMac/Features/Emoji/Model/EmojiData.generated.swift \
                           GearMac/Features/Emoji/Service/EmojiIndex.swift \
                           GearMac/Features/Emoji/Service/FrequentEmojiStore.swift \
                           GearMac/Features/Launcher/Model/SearchRelevance.swift \
                           GearMac/Platform/AppPaths.swift GearMac/Platform/Memo.swift
run palette-selection-test GearMac/Features/PaletteRowIndex.swift \
                           GearMac/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Features/Settings/AppAppearance.swift
run interface-size-test    GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Features/Settings/InterfaceSize.swift \
                           GearMac/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Features/Settings/InterfaceSize.swift \
                           GearMac/Palette/PalettePlacement.swift
run scroll-reveal-test     GearMac/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         GearMac/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    GearMac/DesignSystem/Interaction/KeyboardFocus.swift
run ai-instructions-test   GearMac/Features/AI/Model/AIInstructions.swift \
                           GearMac/Features/AI/Model/AIPreamble.swift
run hover-arming-test      GearMac/Palette/HoverArming.swift \
                           GearMac/Palette/PaletteState.swift \
                           GearMac/Palette/PaletteMode.swift \
                           GearMac/Features/Emoji/Model/EmojiCatalog.swift \
                           GearMac/Features/Clipboard/Model/ClipboardStore.swift \
                           GearMac/Features/Clipboard/Model/ClipTag.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFilter.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFileKind.swift \
                           GearMac/Features/FileSearch/Model/FileSearchFilter.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorFormat.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/CustomCommands/Model/CustomCommand.swift
run palette-escape-test    GearMac/Palette/PaletteMode.swift \
                           GearMac/Palette/PaletteEscapeAction.swift \
                           GearMac/Palette/CommandEscapeTap.swift \
                           GearMac/Features/Settings/EscapeKeyBehavior.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test GearMac/Palette/PaletteState.swift \
                           GearMac/Palette/PaletteMode.swift \
                           GearMac/Palette/HoverArming.swift \
                           GearMac/Features/Emoji/Model/EmojiCatalog.swift \
                           GearMac/Features/Clipboard/Model/ClipboardStore.swift \
                           GearMac/Features/Clipboard/Model/ClipTag.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFilter.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFileKind.swift \
                           GearMac/Features/FileSearch/Model/FileSearchFilter.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorFormat.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    GearMac/Palette/PaletteMode.swift \
                           GearMac/Palette/PaletteFilterAction.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/CustomCommands/Model/CustomCommand.swift
run action-menu-search-test GearMac/Palette/ActionMenuSearchQuery.swift \
                            GearMac/Features/Launcher/Model/SearchRelevance.swift
run palette-shortcut-test  GearMac/Palette/PaletteShortcut.swift
run ascii-layout-test      GearMac/Platform/ASCIIKeyboardLayout.swift
run palette-tab-test       GearMac/Palette/PaletteMode.swift \
                           GearMac/Palette/PaletteTabAction.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/CustomCommands/Model/CustomCommand.swift
run fallback-test          GearMac/Features/Launcher/Model/Fallback.swift \
                           GearMac/Features/Launcher/Model/CommandID.swift \
                           GearMac/Features/HotKeys/Model/HotKeyAction.swift \
                           GearMac/Features/QuickActions/Model/QuickAction.swift \
                           GearMac/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           GearMac/Features/QuickActions/Model/CustomQuickAction.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/SystemActions/Model/SystemAction.swift \
                           GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/Snippets/Model/Snippet.swift
run dictionary-test        GearMac/Features/Dictionary/Model/DictionaryEntry.swift \
                           GearMac/Features/Dictionary/Model/DictionaryMarkup.swift
run dictation-test         GearMac/Features/Dictation/Model/DictationModel.swift GearMac/Features/Dictation/Model/DictationIdleRelease.swift GearMac/Features/Dictation/Model/DictationTextFormatter.swift
run dictation-field-test   GearMac/Features/Dictation/Model/DictationModel.swift \
                           GearMac/Features/Dictation/Model/DictationMode.swift \
                           GearMac/Features/Dictation/Model/DictationDestination.swift \
                           GearMac/Features/Dictation/Model/DictationTextFormatter.swift \
                           GearMac/Features/Dictation/Service/DictationCoordinator.swift \
                           GearMac/Features/Dictation/Service/DictationInsertionContext.swift \
                           GearMac/Features/AI/UI/ChatComposerTextView.swift \
                           GearMac/Features/TextInjection/Service/*.swift \
                           GearMac/Features/Snippets/Model/*.swift \
                           GearMac/Platform/AccessibilityText.swift \
                           GearMac/Platform/PasteboardFiles.swift \
                           GearMac/Platform/Appearance.swift GearMac/DesignSystem/Theme.swift
run dictation-volume-test  GearMac/Features/Dictation/Model/DictationVolumeSnapshot.swift \
                           GearMac/Features/Dictation/Service/DictationAudioDucker.swift \
                           GearMac/Platform/AppPaths.swift
run index -O dictation-performance GearMac/Platform/ProcessExit.swift \
                           GearMac/Features/Dictation/Model/DictationModel.swift \
                           GearMac/Features/Dictation/Service/DictationWire.swift
run dictation-inference-test GearMac/Features/Dictation/Model/DictationAudioChunks.swift \
    GearMac/Features/Dictation/Service/DictationSpectrum.swift \
    GearMac/Features/Dictation/Helper/DictationTensor.swift GearMac/Features/Dictation/Helper/DictationTokenizer.swift \
    GearMac/Features/Dictation/Helper/DictationMel.swift
run dictation-worker-test  GearMac/Features/Dictation/Model/DictationModel.swift \
                           GearMac/Features/Dictation/Model/DictationIdleRelease.swift \
                           GearMac/Features/Dictation/Service/DictationWire.swift \
                           GearMac/Features/Dictation/Service/DictationWorker.swift \
                           GearMac/Features/Dictation/Service/DictationModelStore.swift \
                           GearMac/Features/Dictation/Service/DictationModelDownloader.swift \
                           GearMac/Platform/ProcessExit.swift GearMac/Platform/AppPaths.swift
run hotkey-test            GearMac/Features/HotKeys/Model/DoubleTapModifier.swift \
                           GearMac/Features/HotKeys/Model/ModifierKey.swift \
                           GearMac/Features/HotKeys/Model/ModifierKeyDetector.swift \
                           GearMac/Features/HotKeys/Model/DoubleTapDetector.swift \
                           GearMac/Features/HotKeys/Model/HotKeyBinding.swift \
                           GearMac/Features/HotKeys/Model/HotKeySpelling.swift \
                           GearMac/Features/HotKeys/Model/HyperKey.swift \
                           GearMac/Platform/ASCIIKeyboardLayout.swift \
                           GearMac/Features/HotKeys/Service/KeyShortcut.swift \
                           GearMac/Features/HotKeys/Model/HotKeyAction.swift \
                           GearMac/Features/QuickActions/Model/QuickAction.swift \
                           GearMac/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           GearMac/Features/QuickActions/Model/CustomQuickAction.swift \
                           GearMac/Features/Launcher/Model/CommandID.swift \
                           GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/SystemActions/Model/SystemAction.swift \
                           GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/Snippets/Model/Snippet.swift
run callout-test          GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        GearMac/Platform/Appearance.swift \
                           GearMac/Platform/Images/IconCache.swift
run entry-icon-test        GearMac/Platform/Appearance.swift \
                           GearMac/Platform/Images/IconCache.swift \
                           GearMac/Platform/Images/FileIconStamp.swift
run ext-icon-test          GearMac/Platform/Appearance.swift \
                           GearMac/Platform/AppDisplayName.swift \
                           GearMac/Platform/Images/IconCache.swift \
                           GearMac/Platform/Compression/Zlib.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Features/Extensions/Model/ExtensionBootConfig.swift \
                           GearMac/Features/Extensions/Model/ExtensionLaunchType.swift \
                           GearMac/Features/Extensions/Model/ExtensionManifest.swift \
                           GearMac/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           GearMac/Features/Extensions/Model/ExtensionRefreshState.swift \
                           GearMac/Features/Extensions/Model/RenderNode.swift \
                           GearMac/Features/Extensions/Service/ExtensionCatalog.swift \
                           GearMac/Features/Extensions/Service/ExtensionFetcher.swift \
                           GearMac/Platform/ProcessExit.swift \
                           GearMac/Features/Extensions/Service/ExtensionNodeShims.swift \
                           GearMac/Features/Extensions/Service/ExtensionOAuthKeychain.swift \
                           GearMac/Features/Extensions/Service/ExtensionOAuthSession.swift \
                           GearMac/Features/Extensions/Service/ExtensionRuntime.swift \
                           GearMac/Features/Extensions/Service/ExtensionIconCache.swift \
                           GearMac/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           GearMac/Features/Extensions/UI/ExtensionImage.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift
run system-action-test     GearMac/Features/SystemActions/Model/SystemAction.swift
run microphone-mute-test   GearMac/Features/SystemActions/Service/SystemActionFailure.swift \
                           GearMac/Features/SystemActions/Service/SystemActionRunner+Microphone.swift
run volume-test            GearMac/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/WindowManagement/Model/WindowCycle.swift \
                           GearMac/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           GearMac/Features/WindowManagement/Model/WindowActionMemory.swift
run window-preset-test     GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/WindowManagement/Model/WindowShortcutPreset.swift \
                           GearMac/Features/HotKeys/Model/DoubleTapModifier.swift \
                           GearMac/Features/HotKeys/Model/ModifierKey.swift \
                           GearMac/Features/HotKeys/Model/HotKeyBinding.swift \
                           GearMac/Features/HotKeys/Model/HyperKey.swift \
                           GearMac/Platform/ASCIIKeyboardLayout.swift \
                           GearMac/Features/HotKeys/Service/KeyShortcut.swift
run space-gesture-test     GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/WindowManagement/Model/SpaceGesture.swift
run window-layout-test     GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/WindowManagement/Model/WindowCycle.swift \
                           GearMac/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayout.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           GearMac/Features/WindowManagement/Model/CustomWindowSize.swift \
                           GearMac/Features/WindowManagement/Model/CustomWindowSizeStore.swift
run window-room-test       GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/WindowManagement/Model/WindowCycle.swift \
                           GearMac/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayout.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           GearMac/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           GearMac/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           GearMac/Features/WindowManagement/Model/RoomGrid.swift \
                           GearMac/Features/WindowManagement/Model/RoomWindow.swift \
                           GearMac/Features/WindowManagement/Model/Room.swift \
                           GearMac/Features/WindowManagement/Model/RoomWindowMatcher.swift \
                           GearMac/Features/WindowManagement/Model/RoomParking.swift \
                           GearMac/Features/WindowManagement/Model/RoomPlan.swift \
                           GearMac/Features/WindowManagement/Model/RoomArrangement.swift \
                           GearMac/Features/WindowManagement/Model/RoomStore.swift \
                           GearMac/Features/WindowManagement/Model/RoomMinimumSizeStore.swift \
                           GearMac/Features/WindowManagement/Model/RoomParkingLedger.swift
run window-file-test       GearMac/Features/WindowManagement/Model/WindowCommand.swift \
                           GearMac/Features/WindowManagement/Model/WindowCycle.swift \
                           GearMac/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayout.swift \
                           GearMac/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           GearMac/Features/WindowManagement/Model/CustomWindowSize.swift \
                           GearMac/Features/WindowManagement/Model/Room.swift \
                           GearMac/Features/WindowManagement/Model/RoomWindow.swift \
                           GearMac/Features/WindowManagement/Model/RoomLayoutKind.swift \
                           GearMac/Features/WindowManagement/Model/RoomGrid.swift \
                           GearMac/Features/WindowManagement/Model/RoomLayoutEngine.swift \
                           GearMac/Features/WindowManagement/Model/WindowManagementFileFormat.swift \
                           GearMac/Features/Settings/Model/SettingsFileJSON.swift \
                           GearMac/Features/Settings/Model/SettingsFileIdentity.swift
run custom-command-test    GearMac/Platform/PseudoTerminal.swift \
                           GearMac/Platform/ProcessExit.swift \
                           GearMac/Features/CustomCommands/Model/CustomCommand.swift \
                           GearMac/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           GearMac/Features/CustomCommands/Service/ShellCommandRunner.swift
run uninstall-test         GearMac/Features/Uninstall/Model/UninstallTarget.swift \
                           GearMac/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           GearMac/Features/Uninstall/Model/UninstallRules.swift \
                           GearMac/Features/Uninstall/Model/UninstallProtection.swift \
                           GearMac/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkStore.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           GearMac/Features/Quicklinks/Model/RaycastQuicklinkImport.swift
run quicklink-coordinator-test GearMac/Features/Quicklinks/Model/Quicklink.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkStore.swift \
                           GearMac/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           GearMac/Features/Quicklinks/UI/QuicklinkCoordinator.swift \
                           GearMac/Features/Quicklinks/UI/QuicklinkArgumentsAccessory.swift \
                           GearMac/Features/Snippets/Model/Snippet.swift \
                           GearMac/Features/Snippets/Model/SnippetTemplateEngine.swift
run slow snippets-test     GearMac/Platform/NotificationToken.swift \
                           GearMac/Platform/HealthTicker.swift \
                           GearMac/Platform/AccessibilityText.swift \
                           GearMac/Features/Snippets/Model/*.swift \
                           GearMac/Features/Snippets/Service/*.swift \
                           GearMac/Features/TextInjection/Service/*.swift
run notes-test             GearMac/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           GearMac/Features/Notes/Model/*.swift \
                           GearMac/Features/Notes/Service/*.swift
run notes-editor-test      GearMac/Platform/Signposts.swift \
                           GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Platform/NotificationToken.swift \
                           GearMac/Features/TextInjection/Service/InjectableTextView.swift \
                           GearMac/Features/Notes/Model/NoteDocument.swift \
                           GearMac/Features/Notes/Model/NoteMarkdown.swift \
                           GearMac/Features/Notes/Model/NoteMarkdownParser.swift \
                           GearMac/Features/Notes/Model/NoteInlineScanner.swift \
                           GearMac/Features/Notes/Model/NoteEditPlan.swift \
                           GearMac/Features/Notes/Model/NoteEditAction.swift \
                           GearMac/Features/Notes/Model/NoteFormatting.swift \
                           GearMac/Features/Notes/Model/NoteMarkdownEditing.swift \
                           GearMac/Features/Notes/Model/NoteRevealPolicy.swift \
                           GearMac/Features/Notes/UI/NoteMarkdownTypography.swift \
                           GearMac/Features/Notes/UI/NoteBlockDecoration.swift \
                           GearMac/Features/Notes/UI/NoteMarkdownStyler.swift \
                           GearMac/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           GearMac/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           GearMac/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           GearMac/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           GearMac/Features/Notes/UI/NoteTextViewEditing.swift \
                           GearMac/Features/Notes/UI/NoteTextView.swift \
                           GearMac/Features/Notes/UI/NoteEditorView.swift
run -O index notes-editor-performance \
                           GearMac/Platform/Signposts.swift \
                           GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Platform/NotificationToken.swift \
                           GearMac/Features/TextInjection/Service/InjectableTextView.swift \
                           GearMac/Features/Notes/Model/NoteDocument.swift \
                           GearMac/Features/Notes/Model/NoteMarkdown.swift \
                           GearMac/Features/Notes/Model/NoteMarkdownParser.swift \
                           GearMac/Features/Notes/Model/NoteInlineScanner.swift \
                           GearMac/Features/Notes/Model/NoteEditPlan.swift \
                           GearMac/Features/Notes/Model/NoteEditAction.swift \
                           GearMac/Features/Notes/Model/NoteFormatting.swift \
                           GearMac/Features/Notes/Model/NoteMarkdownEditing.swift \
                           GearMac/Features/Notes/Model/NoteRevealPolicy.swift \
                           GearMac/Features/Notes/UI/NoteMarkdownTypography.swift \
                           GearMac/Features/Notes/UI/NoteBlockDecoration.swift \
                           GearMac/Features/Notes/UI/NoteMarkdownStyler.swift \
                           GearMac/Features/Notes/UI/NoteMarkdownRenderer.swift \
                           GearMac/Features/Notes/UI/NoteCheckboxGeometry.swift \
                           GearMac/Features/Notes/UI/NoteBlockLayoutFragment.swift \
                           GearMac/Features/Notes/UI/NoteLayoutFragmentProvider.swift \
                           GearMac/Features/Notes/UI/NoteTextViewEditing.swift \
                           GearMac/Features/Notes/UI/NoteTextView.swift \
                           GearMac/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   GearMac/Features/Backup/Model/RaycastImportError.swift \
                           GearMac/Features/Backup/Service/RaycastDecoder.swift \
                           GearMac/Features/Backup/Service/Scrypt.swift \
                           GearMac/Platform/Compression/Zlib.swift \
                           GearMac/Features/Clipboard/Model/RaycastClipboardImport.swift \
                           GearMac/Features/Clipboard/Model/ClipboardStore.swift \
                           GearMac/Features/Clipboard/Model/ClipTag.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFilter.swift \
                           GearMac/Features/Clipboard/Model/ClipboardFileKind.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorFormat.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift
run settings-backup-test   GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/Backup/Model/SettingsBackupCoverage.swift
run settings-file-test     GearMac/Features/Settings/Model/*.swift \
                           GearMac/Features/Settings/Service/SettingsFileMonitor.swift \
                           GearMac/Features/Settings/Service/SettingsFileRepository.swift \
                           GearMac/Platform/AppPaths.swift
run backup-archive-test    GearMac/Platform/AppPaths.swift \
                           GearMac/Features/Backup/Model/BackupArchive.swift \
                           GearMac/Features/Backup/Model/BackupBundle.swift \
                           GearMac/Features/Backup/Model/BackupCategory.swift \
                           GearMac/Features/Backup/Model/BackupClipboardItem.swift \
                           GearMac/Features/Backup/Model/BackupManifest.swift \
                           GearMac/Features/Backup/Service/BackupStaging.swift
# Extensions 叶子路径的简写。
E=GearMac/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           GearMac/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           GearMac/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-version-test       $E/Model/ExtensionListing.swift \
                           $E/Service/ExtensionVersionStore.swift
run ext-store-test         $E/Model/ExtensionGitHubSource.swift \
                           $E/Model/ExtensionListing.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-image-size-test   $E/Model/ExtensionImageSize.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Tests/ext-menu-bar-test.swift \
                           Tests/ext-fetch-test.swift \
                           $E/Model/ExtensionLaunchError.swift \
                           $E/Model/ExtensionMenuBarSnapshot.swift \
                           $E/Service/ExtensionStorage.swift \
                           $E/Service/ExtensionMenuBarManager.swift \
                           $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift \
                           $E/UI/ExtensionMenuBarController.swift \
                           $E/UI/ExtensionMenuBarImage.swift \
                           GearMac/Platform/Appearance.swift \
                           GearMac/Platform/AppDisplayName.swift \
                           GearMac/Platform/Images/IconCache.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionManifest.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           GearMac/Platform/ProcessExit.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionOAuthKeychain.swift \
                           $E/Service/ExtensionOAuthSession.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/Service/ExtensionNameResolver.swift \
                           $E/Service/ExtensionWebSocketBridge.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           GearMac/Platform/Compression/Zlib.swift \
                           GearMac/Features/Clipboard/Model/ColorValue.swift \
                           GearMac/Features/Clipboard/Model/ColorSpaces.swift
run settings-history-test  GearMac/Features/Settings/SettingsTab.swift \
                           GearMac/Features/Settings/SettingsHistory.swift \
                           GearMac/Features/Settings/SettingsAnchor.swift \
                           GearMac/Features/Settings/SettingsNavigationState.swift \
                           GearMac/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift
run updates-test           GearMac/Features/Updates/Model/*.swift \
                           GearMac/Features/Updates/Service/BundleSignature.swift
run update-check-test      GearMac/Features/Updates/Model/*.swift \
                           GearMac/Features/Updates/Service/UpdateCheckStore.swift \
                           GearMac/Platform/AppPaths.swift
run support-test           GearMac/Features/Support/Model/*.swift
run decisions-test         GearMac/Features/AI/Model/Decisions.swift
run ai-provider-test       GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/AI/Model/*.swift \
                           GearMac/Features/AI/Settings/AISettingsStore.swift
run ai-chat-test           GearMac/Features/AI/Model/AIRequest.swift \
                           GearMac/Features/AI/Model/AIConnection.swift \
                           GearMac/Features/AI/Model/Decisions.swift \
                           GearMac/Features/AI/Model/AppleIntelligence.swift \
                           GearMac/Features/AI/Model/AIAttachmentPolicy.swift \
                           GearMac/Features/AI/Model/AIRetention.swift \
                           GearMac/Features/AI/Model/AITool.swift \
                           GearMac/Features/AI/Model/JSONValue.swift \
                           GearMac/Features/AI/Model/ChatMessage.swift \
                           GearMac/Features/AI/Model/ChatSession.swift \
                           GearMac/Features/AI/Model/ChatChoices.swift \
                           GearMac/Features/AI/Model/ChatReferences.swift \
                           GearMac/Features/AI/Model/ChatTitle.swift \
                           GearMac/Features/AI/Model/ChatFind.swift \
                           GearMac/Features/AI/Model/ChatCitations.swift \
                           GearMac/Features/AI/Model/ChatToolScope.swift \
                           GearMac/Features/AI/Model/MarkdownBlock.swift \
                           GearMac/Features/AI/Model/MarkdownMath.swift \
                           GearMac/Features/AI/Model/MathFormula.swift \
                           GearMac/Features/AI/Model/MathNode.swift \
                           GearMac/Features/AI/Model/MathSymbolCatalog.swift \
                           GearMac/Features/AI/Service/AIProvider.swift \
                           GearMac/Features/AI/Service/ChatHistoryStore.swift \
                           GearMac/Features/AI/Service/AIToolLoopProvider.swift \
                           GearMac/Features/AI/UI/AIChatState.swift \
                           GearMac/Features/AI/UI/AIChatSurfacesState.swift \
                           GearMac/Features/AI/UI/ChatFindState.swift
run chat-markdown-test     GearMac/Platform/Appearance.swift \
                           GearMac/DesignSystem/Theme.swift \
                           GearMac/DesignSystem/InterfaceMetrics.swift \
                           GearMac/Features/Settings/InterfaceSize.swift \
                           GearMac/Features/AI/Model/AIRequest.swift \
                           GearMac/Features/AI/Model/AITool.swift \
                           GearMac/Features/AI/Model/JSONValue.swift \
                           GearMac/Features/AI/Model/ChatMessage.swift \
                           GearMac/Features/AI/Model/ChatChoices.swift \
                           GearMac/Features/AI/Model/ChatReferences.swift \
                           GearMac/Features/AI/Model/ChatCitations.swift \
                           GearMac/Features/AI/Model/ChatFind.swift \
                           GearMac/Features/AI/Model/MarkdownBlock.swift \
                           GearMac/Features/AI/Model/MarkdownMath.swift \
                           GearMac/Features/AI/Model/MathFormula.swift \
                           GearMac/Features/AI/Model/MathNode.swift \
                           GearMac/Features/AI/Model/MathSymbolCatalog.swift \
                           GearMac/Features/AI/UI/ChatTextHighlight.swift \
                           GearMac/Features/AI/UI/ChatMarkdownRenderer.swift \
                           GearMac/Features/AI/UI/MathAttachmentCell.swift \
                           GearMac/Features/AI/UI/MathBox.swift \
                           GearMac/Features/AI/UI/MathFont.swift \
                           GearMac/Features/AI/UI/MathLayoutEngine.swift
run mcp-test               GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/AI/Model/AIConnection.swift \
                           GearMac/Features/AI/Model/Decisions.swift \
                           GearMac/Features/AI/Model/AppleIntelligence.swift \
                           GearMac/Features/AI/Model/AITool.swift \
                           GearMac/Features/AI/Model/AIToolServer.swift \
                           GearMac/Features/AI/Model/JSONValue.swift \
                           GearMac/Features/MCP/Model/*.swift \
                           GearMac/Features/MCP/Settings/MCPSettingsStore.swift
run -O text-diff-test      GearMac/Features/QuickActions/Model/TextDiffEngine.swift
run index text-diff-performance GearMac/Features/QuickActions/Model/TextDiffEngine.swift
run quick-action-test      GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/AI/Model/AIConnection.swift \
                           GearMac/Features/AI/Model/Decisions.swift \
                           GearMac/Features/AI/Model/AppleIntelligence.swift \
                           GearMac/Features/AI/Model/ChatGPTSubscription.swift \
                           GearMac/Features/AI/Model/InstalledAI.swift \
                           GearMac/Features/QuickActions/Model/*.swift \
                           GearMac/Features/QuickActions/Settings/QuickActionSettingsStore.swift
run apple-intelligence-test GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/AI/Model/*.swift \
                           GearMac/Features/AI/Service/AIProvider.swift \
                           GearMac/Features/AI/Service/AppleIntelligenceProvider.swift
run mcp-oauth-test         GearMac/Platform/ExecutableLocator.swift \
                           GearMac/Platform/ProcessExit.swift \
                           GearMac/Platform/KeychainSecretStore.swift \
                           GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/AI/Model/AIConnection.swift \
                           GearMac/Features/AI/Model/Decisions.swift \
                           GearMac/Features/AI/Model/AppleIntelligence.swift \
                           GearMac/Features/AI/Model/AITool.swift \
                           GearMac/Features/AI/Model/AIToolServer.swift \
                           GearMac/Features/AI/Model/AIStreamDecoder.swift \
                           GearMac/Features/AI/Model/AIThinkTagDecoder.swift \
                           GearMac/Features/AI/Model/AIRequest.swift \
                           GearMac/Features/AI/Model/JSONValue.swift \
                           GearMac/Features/MCP/Model/*.swift \
                           GearMac/Features/MCP/Service/*.swift
run slow mcp-stdio-test    GearMac/Platform/ExecutableLocator.swift \
                           GearMac/Platform/ProcessExit.swift \
                           GearMac/Platform/KeychainSecretStore.swift \
                           GearMac/Features/Settings/AppSettingsKey.swift \
                           GearMac/Features/AI/Model/AIConnection.swift \
                           GearMac/Features/AI/Model/Decisions.swift \
                           GearMac/Features/AI/Model/AppleIntelligence.swift \
                           GearMac/Features/AI/Model/AITool.swift \
                           GearMac/Features/AI/Model/AIToolServer.swift \
                           GearMac/Features/AI/Model/AIStreamDecoder.swift \
                           GearMac/Features/AI/Model/AIThinkTagDecoder.swift \
                           GearMac/Features/AI/Model/AIRequest.swift \
                           GearMac/Features/AI/Model/JSONValue.swift \
                           GearMac/Features/MCP/Model/*.swift \
                           GearMac/Features/MCP/Service/*.swift
run slow codex-turn-test   GearMac/Platform/AppPaths.swift \
                           GearMac/Features/AI/Model/*.swift \
                           GearMac/Features/AI/Service/AIProvider.swift \
                           GearMac/Features/AI/Service/ChatGPTSubscriptionManager.swift \
                           GearMac/Features/AI/Service/CodexAppServerClient.swift \
                           GearMac/Features/AI/Service/InstalledAIProbe.swift \
                           GearMac/Platform/ExecutableLocator.swift \
                           GearMac/Platform/ProcessExit.swift \
                           GearMac/Features/AI/Service/CodexTurnRunner.swift
run installed-ai-test     GearMac/Features/AI/Model/*.swift \
                          GearMac/Features/AI/Service/AIProvider.swift \
                          GearMac/Platform/AppPaths.swift \
                          GearMac/Platform/ExecutableLocator.swift \
                          GearMac/Platform/ProcessExit.swift \
                          GearMac/Features/AI/Service/InstalledCLIProvider.swift \
                          GearMac/Features/AI/Service/InstalledAIProbe.swift \
                          GearMac/Features/AI/Service/InstalledAIManager.swift

if [ "$emit_db" -eq 1 ]; then
    # 收尾：把临时收集的条目与 .compile 中已有的非 Tests/ 条目合并写回。
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

# 一个 harness 都没跑（名字拼错）时报错退出。
if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` 是稳定排序，所以慢 harness 排在前面，其余保持声明顺序。
# 并行 worker 数，默认 4。
JOBS="${GEARMAC_TEST_JOBS:-4}"
# 单个 harness 的执行超时（秒），超时即判失败。
export GEARMAC_TEST_TIMEOUT="${GEARMAC_TEST_TIMEOUT:-300}"
started=$SECONDS

# 给每条结果编号，并在输出安静下来时列出仍在运行的 harness。
report() {
    # 读入编号后的结果行；连续 15 秒没输出就报一次「仍在运行」。
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # bash 3.2 对超时和 EOF 返回同样的状态；只有 EOF 会立刻返回。
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

# 没有这段，派发本身挂掉、一个 harness 都没跑时，套件会报告「全部通过」。
if ! { sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; echo "dispatch $?"; } | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# 编译器诊断远长于 PIPE_BUF，所以 worker 把它写进日志，在这里回放。
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
