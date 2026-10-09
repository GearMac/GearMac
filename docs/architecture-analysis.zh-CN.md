# GearMac 架构设计分析（基于源码）

> 本文不是 `architecture.md` 的翻译，而是直接读取当前源码、`project.yml`、`Info.plist`、`GearMac.entitlements` 和各功能目录后整理的独立分析。它侧重“架构为什么这样设计、靠什么机制维持”，并给出可核对的量化事实。
>
> 统计口径为源码实测（`find`/`grep`），随代码演进会有小幅漂移。功能级不变量仍以 `docs/features/` 与源码为准。

---

## 目录

1. [产品定位与架构目标](#1-产品定位与架构目标)
2. [技术基线与工程约束](#2-技术基线与工程约束)
3. [组合根与单一所有权](#3-组合根与单一所有权)
4. [四层分层模型](#4-四层分层模型)
5. [强制机制：为什么边界不会漂移](#5-强制机制为什么边界不会漂移)
6. [并发模型](#6-并发模型)
7. [状态与观察模型](#7-状态与观察模型)
8. [命令面板：核心交互架构](#8-命令面板核心交互架构)
9. [窗口与呈现表面](#9-窗口与呈现表面)
10. [进程边界：helper 拆分](#10-进程边界helper-拆分)
11. [扩展运行时的隔离边界](#11-扩展运行时的隔离边界)
12. [功能地图与规模数据](#12-功能地图与规模数据)
13. [持久化与设置文件镜像](#13-持久化与设置文件镜像)
14. [生成文件与脚本](#14-生成文件与脚本)
15. [测试架构：harness 而非 XCTest](#15-测试架构harness-而非-xctest)
16. [构建、渠道与签名](#16-构建渠道与签名)
17. [架构评价：设计取舍与风险点](#17-架构评价设计取舍与风险点)
18. [维护者阅读路径](#18-维护者阅读路径)
19. [中文注释规范与标注范围](#19-中文注释规范与标注范围)

---

## 1. 产品定位与架构目标

GearMac 是一个只面向当前稳定版 macOS（部署目标 macOS 26.0）的原生菜单栏启动器，以 accessory 应用（`LSUIElement = true`）运行，不在 Dock 常驻。它的能力边界很宽——模糊应用启动、全局/应用级快捷键、文本与图片剪贴板历史、内联计算器、笔记、片段、快速链接、窗口管理、Emoji 选择器、日历/会议、听写、AI 对话、Quick Actions，以及**在 JavaScriptCore 中原生运行 Raycast 扩展**。

但从源码看，它并不是“功能堆叠型”项目，而是围绕四条架构目标收敛的：

| 目标 | 源码中的体现 |
| --- | --- |
| **零第三方依赖** | 全项目 Swift 源码，无 SwiftPM 依赖、无 CocoaPods；唯一外部运行时是自建的 JS 扩展运行时 |
| **单一所有权** | 全仓库仅 `AppCore.swift` 出现一次 `static let shared` |
| **决策与副作用可强制分离** | `Model/` 禁止 import AppKit/SwiftUI，且由 harness 编译强制 |
| **只面向最新平台** | 无兼容层、无版本判断、无迁移脚手架；直接使用 Observation、Swift Concurrency、`SMAppService` |

**latest-only 姿态**是理解整个代码库的钥匙。项目明确定义“deprecated API 即缺陷”，迁移而不包装。这条规则直接解释了为什么代码量能维持在较低水平（约 11.8 万行 Swift，含注释与生成数据）：不需要为旧系统保留第二套实现。

**架构的实质目标是控制“长寿命状态的爆炸”。** 一个功能如此密集的启动器，最危险的不是单个功能写错，而是几十个功能各自持有生命周期、各自注册快捷键、各自监听系统事件，最终无人能说清“谁在什么时候启动了什么”。GearMac 用组合根 + 协调器 + 分层强制三件事来对抗这一点。

---

## 2. 技术基线与工程约束

| 维度 | 取值 | 来源 |
| --- | --- | --- |
| 语言 | Swift 6.0，语言模式 6 | `project.yml` `SWIFT_VERSION` / `SWIFT_STRICT_CONCURRENCY: complete` |
| UI | SwiftUI + AppKit 混用 | 各 feature 的 `UI/`、`Palette/`、`Windows/` |
| 部署目标 | macOS 26.0 | `project.yml` `deploymentTarget` |
| 项目生成 | XcodeGen，`GearMac.xcodeproj` 由 `project.yml` 生成并提交 | `project.yml` |
| 依赖 | 无第三方依赖 | 无锁文件、无 Package.swift |
| 最低签名 | 自签名 `GearMac Self-Signed`（手工签名） | `project.yml` `CODE_SIGN_IDENTITY` |
| 沙盒 | **关闭**（`com.apple.security.app-sandbox = false`） | `GearMac.entitlements` |
| 关键 entitlement | JIT、Apple Events、摄像头、麦克风、日历 | `GearMac.entitlements` |

沙盒关闭是刻意选择：作为启动器，它必须调用 `AXUIElement`、注册 Carbon 全局热键、执行 shell 命令、读写任意用户目录、运行扩展。这些能力与 App Store 沙盒模型直接冲突，因此项目走的是直接分发（Homebrew cask / DMG）路线。

`entitlements` 里的每一条都有明确注释解释“为什么必须”，例如 `allow-jit` 是因为 JavaScriptCore 要编译每条扩展命令，`automation.apple-events` 是因为强化的运行时会拒绝所有 Apple Event 且没有提示可恢复。这种“能力声明必须带理由”的注释风格贯穿全库。

---

## 3. 组合根与单一所有权

### 3.1 启动链

```text
GearMacApp (@main, SwiftUI App)
  └─ @NSApplicationDelegateAdaptor → AppDelegate
       └─ applicationDidFinishLaunching → AppCore.shared.start()   ← 唯一启动编排点
```

`AppDelegate`（`GearMac//App/AppDelegate.swift`）只做 AppKit 生命周期事：写入 `AppleShowScrollBars`、把启动交给 `AppCore.shared.start()`、处理 URL 打开、终止前调用 `prepareForTermination()`、处理 Dock 触发的“关闭窗口”语义。它**不持有任何业务状态**。

`GearMacApp` 只声明两个 `MenuBarExtra` 场景（GearMac 自身、日历），其余可见表面全部由 AppKit controller 命令式驱动。同时通过 `.commands` 重绑 ⌘Q 为 “Close Window”（AI Chat 窗口在前后时为关它，否则关设置），且明确注明该主菜单必须保持声明式，因为 SwiftUI 会在任意场景变化时重建菜单。

### 3.2 AppCore 是唯一所有者

`AppCore`（`GearMac//App/AppCore.swift`）是一个 `@MainActor @Observable final class`，`private init()`，通过 `static let shared` 暴露。它持有：

- **Store**：`appIndex`、`clipboardStore`、`snippetsStore`、`quicklinks`、`customCommands`、`favorites`、`visibility`、`aliases`、`launcherRanking`、`calcHistory`、`currencyRates`、`frequentEmoji`、`pinnedEmoji`、`calendarStore`、`windowLayouts`、`rooms`、`customWindowSizes` 等；
- **Manager / Monitor / Clock**：`clipboardManager`、`hotKeys`、`hyperKeyTap`、`runningApps`、`snippetListener`、`meetingClock`、`updateChecker`、`iconStyle`、`regionNumberFormat`；
- **Session / State**：`palette`、`fileSearch`、`dictionary`、`menuSearch`、`windowSwitch`、`uninstall`、`roomSession`、`aiChats`、`aiSettings`、`mcpSettings`；
- **Coordinator**：`paletteCoordinator`、`settingsCoordinator`、`launcherCoordinator`、`clipboardCoordinator`、`extensionCoordinator`、`aiChatCoordinator` 等（实测 34 个以 `Coordinator` 命名的编排类型）；
- **窗口与呈现器**：`windowController`（PaletteWindowController）、`dialogs`（DialogController）、`messageHUD`（MessageHUDController）。

`start()` 读起来就是整个应用的启动序列，在源码中一眼可读：设置外观 → 启动 App 索引 → 应用各功能的启用开关 → 启动汇率/更新/支持提醒 → 装配快捷键回调 → 启动 Carbon 热键与 Hyper Key → 挂接 store 的 `onChange` → `observeFeatureSwitches()` 建立设置变更重投影 → 首次启动引导。所有跨模块的目录连接（`hotKeys.onTogglePalette`、`hotKeys.onRunCommand` 等）都是在这里用闭包接线的。

**关键约定：新增长寿命状态必须放在 `AppCore` 并在 `start()` 中接线，不得再创建第二个单例或容器。** 视图通过 `@Environment(AppCore.self)` 拿到 `AppCore`，但它只被当作协调器的**定位器**使用（`core.quicklinkCoordinator.deleteQuicklink(…)`），而不是让视图绕过协调器直接改 store。读 store 用于渲染是允许的，用 store 做决策则被禁止。

### 3.3 协调器是功能动作的载体

每个功能有明确的 Coordinator，负责把用户意图编排成 store/service 调用、确认弹窗与窗口动作。`AppCore` 只保留“热键到协调器”的闭包接线。这样做的直接收益是：确认门（“你确定吗？”）留在协调器，而 runner 保持纯净可测——`ShellCommandRunner`、`SystemActionRunner` 因此能通过 harness 编译，同时破坏性操作又无法被绕过。

---

## 4. 四层分层模型

成熟子系统统一收敛为四层，`Tests/` 的 harness 是维持它们分离的机制：

```text
┌─ 纯决策层 Model/ ────────────────────────────────────────────────┐
│ 仅 Foundation（数据需要时可用 SQLite3 / CoreGraphics）。          │
│ 时钟、文件、主目录、汇率等环境事实全部作为参数注入。              │
│ 由 harness 逐字编译，因此无法漂移。                              │
└───────────────────────────────┬──────────────────────────────────┘
                                │ 被消费
┌─ 副作用层 Service/ ───────────▼──────────────────────────────────┐
│ 所有平台 I/O：AXUIElement、CGEventTap、NSWorkspace、URLSession、  │
│ FileManager、CoreAudio、进程与网络请求。                          │
└───────────────────────────────┬──────────────────────────────────┘
                                │ 发布
┌─ 可观察状态层 ─────────────────▼──────────────────────────────────┐
│ @MainActor @Observable 的 store / session / index / State 类型     │
└───────────────────────────────┬──────────────────────────────────┘
                                │ 渲染
┌─ 视图层 UI/ + Settings/ ──────▼──────────────────────────────────┐
│ SwiftUI 屏幕、视图，以及各功能的 Coordinator；声明式、薄。         │
└──────────────────────────────────────────────────────────────────┘
```

在目录树里它们对应 `Model/`、`Service/`、`UI/`、`Settings/`；可观察状态归属于拥有它的那一个。

分层规则的实质是：**`Model/` 决定（decide），`Service/` 执行（do）。** `CalcEngine.evaluate` 拿到的是一个已经算好的 `CurrencyRates?`，而不是自己去网络请求；`LauncherRankingStore` 拿到 `now` 和文件 URL；`UninstallRules` 拿到的是目录**名字**而不是 URL；`QuicklinkStore` 拿到的是主目录。这既让纯层可测，也保证“决策”不依赖“环境”。

两个东西刻意放在功能目录之外：`Features/PaletteRowIndex.swift`（因为扁平选择索引属于调色板整体而非某个功能），以及 `DesignSystem/` 与 `Platform/`（共享视觉原语与系统适配层）。这两个目录不得反向依赖任何功能。

---

## 5. 强制机制：为什么边界不会漂移

架构文档写得再好，如果只靠自觉就会腐化。GearMac 用**编译**而不是约定来强制边界：

1. `Tests/` 下 106 个 harness **逐字编译被守护的产品源码**（`swiftc … Tests/<name>.swift`），而不是编译一份副本。
2. 因此，一旦有人往 `Model/` 引入了 AppKit 或 SwiftUI，harness 就编译不过——纯层的泄漏会立刻变成编译失败。
3. AGENTS.md 把这条写成了可执行检查：`grep -rln 'import AppKit\|import SwiftUI\|import Cocoa' GearMac//Features/*/Model/` 必须返回空。

我实测该 grep 在当前源码上**无任何违规**。这是全项目最强的架构约束之一：边界不是靠 code review 维持，而是靠构建失败维持。

配套的其他硬性检查：

- `./Scripts/run-tests.sh` 必须通过；
- Debug 构建不得引入新 warning；
- `./Scripts/lint.sh` 必须干净；
- 任何被改动导致失真的文档必须在同一提交内修正。

---

## 6. 并发模型

目标以 **Swift 6 语言模式**编译，数据竞争是硬错误，`SWIFT_STRICT_CONCURRENCY: complete`。

- 默认 `@MainActor`：实测 242 个文件含 `@MainActor`；
- 跨 actor 的模型类型是 `Sendable`（`CalcResult` 等显式标注）；
- 重 CPU/IO 工作以 `nonisolated` 函数由 `Task.detached` 推离主线程（全库 80 处 `Task.detached`、166 处 `nonisolated`），典型如 App 扫描、图像解码、设置面板扫描、shell 执行、汇率拉取；
- **全客户端只有一个 actor，是刻意的**——不引入第二个 actor 来“并行化”。

针对危险边缘的固定惯用法：

| 场景 | 惯用法 |
| --- | --- |
| 块观察者生命周期 | RAII 的 `NotificationToken`，而不是在 `deinit` 里手动移除 |
| SQLite 资源 | `ClipboardStore` 用 `isolated deinit` 收尾 |
| 原始 Carbon / C 指针 | 进入 actor 前解码为普通值（如 `hotKeyCarbonEventHandler`） |
| 周期健康检查 | 共享的 `HealthTicker`，避免每个事件 tap 各持一个定时器 |

`AppCore.track` 是“在视图之外响应设置变化”的标准模式。这里有一个易错的实现细节被明确注释：`withObservationTracking` 的 `onChange` 是 **willSet** 钩子——它在写入落盘前触发且只触发一次，所以闭包必须把重读推迟到 `Task` 里并在其中重新挂起跟踪；去掉 `Task` 会读到旧值。

---

## 7. 状态与观察模型

全库使用 Swift Observation（`@Observable`，实测 79 处注解），**不使用** `ObservableObject` 或 `@Published`，视图通过 `@Environment`（而非 `@EnvironmentObject`）读取。

源码中标注了三个容易踩的坑，值得任何维护者记住：

1. **memo 缓存与懒构建协作者要加 `@ObservationIgnored`**。否则读取缓存本身会注册依赖，导致视图因“自己的缓存被填充”而重渲染。`AppCore` 的所有懒加载协调器都是 `@ObservationIgnored private(set) lazy`，正是为此。
2. **不要给 `@Observable` 值的 `@Environment` 标注类型**。宏按类型解析无键重载，显式标注会改变选中的重载。
3. **编译器看不到漏掉的注入点**。视图读取 `@Environment(AppSettings.self)` 而所在层级无人注入时，编译通过但运行时崩溃；新增 hosting view 时必须检查注入。

外观（appearance）也走同一套：`AppCore.applyAppearance()` 把 `settings.appearance` 赋给 `NSApp.appearance`，`.system` 赋 `nil` 让 AppKit 自己跟随 macOS，全应用没有别的地方设置外观。`IconStyleMonitor` / `IconCache.setDarkSurface` 通过 KVO 监听 `effectiveAppearance` 同步图标缓存，注释解释了为什么不能在 `applyAppearance()` 里做（`.system` 下后者从不触发）。

---

## 8. 命令面板：核心交互架构

命令面板（Palette）是 GearMac 的核心交互面，也是整个项目抽象最精细的部分。它用一个**窗口**承载十几种**屏幕（screen）**，通过协议把“屏幕有哪些行、主键做什么、有哪些动作、箭头键怎么走”从窗口机制中解耦出来。

### 8.1 窗口机制

`PalettePanel` 是一个无边框浮动 `NSPanel`，通过 `NSHostingView` 承载 SwiftUI，由 `PaletteWindowController` 管理。关键设计点：

- **控制器独占 frame 所有权**。每次显示时把锚点解析一次为左上角，使面板向下生长；hosting view 设 `sizingOptions = []`，否则 SwiftUI 会按内容调整窗口大小，导致紧凑↔展开切换时上边缘漂移。
- **紧凑态与展开态**是同一个窗口的两次 resize（`paletteIsCollapsed`），不是两个窗口。状态真源在 `AppCore`，避免两处不一致。
- **失焦即自动隐藏**（`windowDidResignKey`），除非有 modal 面板持有关键状态。
- 面板是 **non-activating** 的：唤起它不会把自家辅助窗口抬到前面；同时它记录 `previousApp`，作为粘贴目标。

### 8.2 屏幕协议

`PaletteScreen`（`GearMac//Palette/PaletteScreen.swift`）是所有模式的统一接口，`rows` 是可见顺序的唯一真源，扁平选择索引直接索引它。协议方法覆盖：主键动作、⌘↵ 次动作、⌃⌘↵ 第三动作、⌥↵ 保持窗口粘贴、⌘K 动作菜单、Tab 焦点环、箭头键落点、以及屏幕自己提供的 header 附属控件（`PaletteHeaderAccessory`）。协议带默认实现，屏幕只实现它真正需要的方法。

`RootPaletteView` 在 `body` 里**每次渲染只解析一次 screen**（`let screen = screen`），再据此计算选择、是否显示 footer、是否显示 Actions 按钮，从结构上消除“扁平索引与行列表不一致”。

`PaletteMode` 是一个含 19 个 case 的 `enum`（launcher、clipboard、ai、aiHistory、calculatorHistory、emoji、fileSearch、menuSearch、switchWindows、rooms、roomWindows、schedule、meetingDetails、uninstall、quicklinks、snippets、dictionary、extensionCommand 等），每个 case 自带 SF Symbol 与占位文案。

### 8.3 视图内的菜单

面板里打开的 Actions / 过滤器 / 模型菜单**不画在面板内**，而是挂在独立的 `MenuPanel` 窗口上（`MenuPanelController`），通过 `WindowReader` 拿到面板 frame 后定位。“同时最多一个菜单”由单个可选状态 `openMenu` 从结构上保证，无法自相矛盾。菜单内容统一抽象为 `PaletteMenuContent`，扩展 Actions 面板和 Emoji 网格各自实现，避免调色板自身菜单被扩展的形状绑架。

### 8.4 键盘处理

`RootPaletteView` 的 key handler 链是项目里为数不多“长到需要拆分”的地方（注释明确说明拆成 `keyHandlers` / `stateObservers` 是因为单条链超出类型推断能力）。处理覆盖：↑/↓ 带 repeat、←/→ 网格步进、↵ 与 ⌘↵/⌥↵/⌃⌘↵、Esc 的多级语义（`PaletteEscapeAction.resolve`）、Tab、⌘K、⌘1…⌘0 收藏槽、⌘P 过滤器、以及扩展快捷键。

`PaletteShortcut`、`PaletteEscapeAction`、`PaletteTabAction`、`PaletteFilterAction` 都是**可独立测试的解析函数**，把“按了什么键 → 做什么”的决策从视图里抽出来。

---

## 9. 窗口与呈现表面

GearMac 有多个 AppKit 表面，各自生命周期独立：

| 表面 | 载体 | 所有者 |
| --- | --- | --- |
| 命令面板 | 无边框浮动 `NSPanel` | `PaletteWindowController` |
| 设置 / 引导 | 有标题 `NSWindow` | `SettingsCoordinator` / `OnboardingCoordinator` |
| 笔记 | 持久、非激活 `NotesPanel` | `NotesWindowController` |
| AI Chat | `NSSplitViewController` 窗口 | `AIChatCoordinator` |
| 支持窗口 | 有标题 `AppWindowController` | `SupportCoordinator` |
| 更新窗口 | 有标题窗口 | `UpdateCoordinator` |
| 相机 | 无边框非激活 `CameraPanel` | `CameraPreviewController` / `CameraCoordinator` |
| 对话框 | 无边框 `DialogPanel` | `DialogController` |
| HUD | 独立面板 | `MessageHUDController` / `VolumeHUDController`（共享 `HUDPresenter`） |
| 菜单面板 | 独立窗口 | `MenuPanelController` |

**为什么设置窗口用 AppKit 而不是 SwiftUI 的 `Settings` / `Window` 场景？** 源码注释给出理由：对 accessory 应用而言 SwiftUI 的这些场景不可靠。因此设置与引导都是有标题 `NSWindow`，由各自的 `AppWindowController` 承载 SwiftUI 内容。

**“项目自己呈现对话框，绝不用 `NSAlert` 或系统 popover”** 是一条带注释的硬规则：提问走 `DialogController`，报告走 HUD。原因写在 `DialogController.swift` 顶部——`NSAlert` 的嵌套 runloop 会让热键把对话框叠加起来。`DialogController` 的呈现是 `async` 的，不阻塞主 actor，并且在已有一个对话框时会拒绝第二个，从而用状态而非标志位阻止长按热键叠窗。

> **实测的例外**：全库唯一一处 `NSAlert` 在 `Features/Extensions/Service/ExtensionManager.swift` 的 `openWithPicker(path:)` 中，用于“用什么应用打开”的系统文件关联选择器。这是一个被容忍的孤例（系统级打开方式选择器没有等价的自绘实现），不影响“业务对话框不用 NSAlert”这条主线规则。

HUD 与对话框被刻意分开：对话框**询问**，HUD **报告**。`AppCore.showNotice` / `confirm` / `choose` / `reportFailure` / `pickVolume` / `createEvent` 都是转发器，保证 `DialogController` 与 `MessageHUDController` 始终保持单一所有者。

---

## 10. 进程边界：helper 拆分

项目有两个独立的 helper target，把重资源能力的生命周期限制在会退出的进程里：

### 10.1 剪贴板文本识别 helper

- `ClipboardTextWorker`（主进程内，无状态）对每个条目启动一个 `ClipboardTextHelper`；
- helper 从 `Contents/Helpers` 运行，返回前被回收；
- Vision 与 PDFKit 的内存分配因此属于一个**会退出的进程**；
- helper 没有数据库、剪贴板或设置访问权限，只接收输入路径，通过管道返回有界文本。

`project.yml` 里主 target **排除**了 helper 的源码，注释解释了原因：把 helper 源码编进主应用会把 Vision 和 PDFKit 链接进应用——而这正是“识别放到进程外”想避免的。

### 10.2 听写 helper

- 模型适配器（Parakeet/Qwen 等）运行在打包的 `DictationHelper.app` 内；
- 音频与文本通过管道有界传输，麦克风采集、UI 与插入留在主应用；
- `DictationModelStore` 按需启动 helper，在选定的空闲延迟后或切换模型时回收；
- `AppCore` 持有音频闪避器（`DictationAudioDucker`），并在每次启动时恢复音量，即使听写关闭。

进程边界与并发边界是同一设计哲学的两个面：**把重资源、易泄漏、需要特殊权限的东西放到一个可以被杀掉并回收的独立进程里**。

---

## 11. 扩展运行时的隔离边界

运行 Raycast 扩展是本项目最有特色的架构决策。运行时是一个自建的 JavaScriptCore 实现，产物是提交进仓库的 `GearMac//Resources/RaycastRuntime.generated.js`（约 258 KB），由 `Scripts/raycast-runtime/build.mjs` 生成。**运行时被提交，因此构建应用永远不需要 Node。**

架构上最硬的一条是：

> **扩展相关的一切都留在 `Features/Extensions/` 内。** 扩展需要的每个视图、行、菜单、几何与尺寸常量都在那里编写和拥有——不得加进 `DesignSystem/`，不得挂到 `Theme`，不得提升到别处供其他功能复用。

理由是：扩展渲染的是**不受我们控制的第三方代码**，它绝不能迫使启动器表面发生改变。其他界面可以把扩展渲染成一个不透明盒子（`LauncherScreen` 用 `ExtensionArgumentsAccessory` 正是如此），但绝不深入其内部。

因此 `ExtensionActionsPanel` 和 `ExtensionGridGeometry` 存在的原因，正是让调色板自身菜单和 Emoji 网格可以自由变化而不受扩展影响。**为保持隔离而重复一份视图或布局数学，是被明确认可的“正确交易”，也是全项目“不重复”规则唯一让位的地方。**

真正共享的东西被严格限定：`Theme` 的基础令牌、作为这些令牌视图的 `InterfaceMetrics`、作为数据形状的 `PopoverMenuItem`，以及 `Platform/`。任何带“扩展看起来/动起来如何”的东西都不共享。

---

## 12. 功能地图与规模数据

实测规模（`find`/`wc`/`grep`，当前工作区）：

| 指标 | 数值 |
| --- | --- |
| Swift 源文件 | 783 |
| Swift 代码总行数 | 约 117,700 |
| `Features/*/Model` 文件 | 259 |
| `Features/*/Service` 文件 | 144 |
| `Features/*/UI` 文件 | 186 |
| `Features/*/Settings` 文件 | 87 |
| 功能目录（`Features/` 下） | 31 个 |
| Coordinator 类型 | 34 |
| `@Observable` 注解 | 79 处 |
| 含 `@MainActor` 的文件 | 242 |
| `nonisolated` 出现 | 166 处 |
| `Task.detached` | 80 处 |
| `Platform/` 文件 | 33 |
| `DesignSystem/` 文件 | 30 |
| `Palette/` + `Windows/` 文件 | 38 |
| 测试 harness | 106 |

规模最大的功能（按 Swift 文件数）：

| 功能 | 文件数 | 说明 |
| --- | --- | --- |
| `AI` | 93 | 模型连接、流式解码、Markdown/数学渲染、工具调用、聊天历史 |
| `Extensions` | 78 | Raycast 运行时桥接、存储、OAuth、菜单栏、表单/网格 |
| `WindowManagement` | 62 | AX 窗口清单、布局、房间、空间切换 |
| `Launcher` | 43 | App 索引、模糊搜索、收藏、别名、排序 |
| `Notes` | 35 | TextKit 2 Markdown 编辑器 |
| `Calculator` | 33 | 词法/表达式、单位、日期、货币 |
| `Settings` | 30 | 设置外壳、设置文件镜像 |
| `Calendar` / `Dictation` | 25 | 日历读取、会议、听写 helper |
| `Clipboard` | 24 | 采集、SQLite 历史、文本索引、粘贴 |
| `MCP` | 22 | MCP 协议、OAuth、stdio/HTTP 传输 |
| `FileSearch` / `QuickActions` / `Backup` / `HotKeys` | 19–20 | — |

功能目录与能力对应关系可参考 `docs/features/` 下每个功能一篇的文档（每篇都以 `## Invariants` 开头，改该区域前必须先读）。

### 12.1 核心功能详解（按能力域）

下面按“用户可见能力”逐项说明每个功能的入口、主要源码位置与关键设计点。入口列的斜体为调色板命令名（`CommandID`），面板模式对应 `PaletteMode` 的 case。

#### 一、入口与交互层

| 功能 | 作用 | 入口 | 主要路径 |
| --- | --- | --- | --- |
| **应用启动器** | 模糊搜索并打开应用/系统设置/命令，支持收藏、别名、使用频次排序、隐藏项 | 全局热键唤起调色板（`.launcher`） | `Features/Launcher/`（`AppIndex`、`LauncherMatch`、`LauncherRankingStore`、`LauncherOrder`） |
| **命令面板（Palette）** | 承载全部面板模式的浮动无边框窗口，是核心交互面 | 全局热键 | `Palette/`（`PaletteScreen`、`RootPaletteView`、`PaletteWindowController`、`PaletteMode`） |
| **全局 / 应用级热键** | 系统级快捷键唤醒、给某应用绑定切换键、Hyper Key | 设置 → 键盘 | `Features/HotKeys/`（`HotKeyManager`、`HyperKeyTap`、Carbon 事件处理） |
| **文本注入** | 把文本/片段粘贴回唤起前的前台应用，含“顺序粘贴” | `Paste Sequentially` | `Features/TextInjection/`（`TextInjector`、`Paster`） |
| **菜单搜索** | 把前台应用的主菜单栏做成可搜索面板 | `Search Menu Bar Items`（`.menuSearch`） | `Features/MenuSearch/` |
| **窗口切换** | 在当前应用的窗口间快速切换 | `Switch Windows`（`.switchWindows`） | `Features/WindowSwitcher/` |

要点：启动器的模糊匹配（`LauncherMatch`/`SearchRelevance`）与排序（`LauncherOrder`）是**纯 Foundation 决策层**，输入是已解析的候选与信号，因此可被 harness 直接编译测试；应用索引扫描 `AppIndex.scan()` 则在 `nonisolated` 工作里跑，避免卡主线程。

#### 二、输入与效率工具

| 功能 | 作用 | 入口 | 主要路径 |
| --- | --- | --- | --- |
| **剪贴板历史** | 文本/图片去重、可搜索、粘贴回原应用 | `Clipboard History`（`.clipboard`） | `Features/Clipboard/`（`ClipboardStore` 用 SQLite、`ClipboardManager`、文本识别 helper） |
| **内联计算器** | 数学、单位、日期、实时货币与加密货币换算 | 直接在调色板输入算式 | `Features/Calculator/`（`CalcEngine`、`CurrencyRateStore`、`CountryZoneData`） |
| **片段（Snippets）** | 可复用 Markdown 模板，支持占位符、参数、嵌套引用与关键词展开 | `Search Snippets`、`Create Snippet` | `Features/Snippets/`（`SnippetTemplateEngine`、`SnippetsStore`、`SnippetKeywordListener`） |
| **快速链接（Quicklinks）** | 把 URL/搜索/文件/deeplink 变成一等命令，支持占位符 | `Search Quicklinks`、`Create Quicklink` | `Features/Quicklinks/` |
| **自定义命令** | 用户定义的具名 shell 命令，可搜索或绑定热键 | `Run Shell Command` | `Features/CustomCommands/`（`ShellCommandRunner`） |
| **快速操作（Quick Actions）** | 对选中文本执行改写、纠错、翻译、总结 | `Fix Grammar` / `Rewrite` / `Translate` / `Summarize` | `Features/QuickActions/` |
| **笔记** | 无限量本地 Markdown 文件，悬浮编辑器，边写边渲染 | `Show Notes`、`Create Note`、`Search Notes` | `Features/Notes/`（TextKit 2 编辑器） |
| **字典** | 用 macOS 自带词典查词 | `Define Word`（`.dictionary`） | `Features/Dictionary/` |
| **文件搜索** | 通过 Spotlight 打开用户选定目录中的文件/文件夹 | `Search Files`（`.fileSearch`） | `Features/FileSearch/` |
| **Emoji 选择器** | 可搜索的 Emoji 网格 | `Search Emoji & Symbols`（`.emoji`） | `Features/Emoji/` |

要点：计算器 `Model/` 是**只 import Foundation 的纯引擎**，由 `CurrencyRateStore` 注入已算好的 `CurrencyRates?`；汇率走私有的 `.ephemeral`、`urlCache = nil` 会话，磁盘上只保留它自己的缓存文件。片段的关键词展开默认关闭，且**授权开关 `snippetsEnabled` 被排除在设置备份之外**，防止“导入即授予键盘监听”。

#### 三、AI 与网络能力

| 功能 | 作用 | 入口 | 主要路径 |
| --- | --- | --- | --- |
| **AI 提供方层** | 全应用统一的文本生成抽象，支持自有密钥或本机已登录的 CLI 账号 | 设置 → AI | `Features/AI/`（93 个文件：provider、流式解码、Markdown/数学渲染、工具调用） |
| **Quick AI / AI Chat** | 面板内快问快答；独立窗口承载长对话，历史可搜索、可固定 | `Quick AI`、`AI Chat`（`.ai` / `.aiHistory`） | `Features/AI/UI/`、`AIChatCoordinator` |
| **MCP** | 连接 Model Context Protocol 服务器并暴露其工具 | 设置 → MCP | `Features/MCP/`（协议、OAuth、stdio/HTTP 传输） |
| **更新检查** | 默认每天查一次 GitHub Releases 并提示新版本 | `Check for Updates` | `Features/Updates/` |
| **支持** | 单一窗口 + 结账链接 + 是否允许自启的开关 | `Support` | `Features/Support/` |

要点：AI 功能**默认关闭**；需要联网的功能统一走私有 `.ephemeral` 会话，磁盘上只有它自己的缓存文件。MCP 的 OAuth 令牌与其他密钥托管在 Keychain（`KeychainSecretStore`）。

#### 四、系统与窗口

| 功能 | 作用 | 入口 | 主要路径 |
| --- | --- | --- | --- |
| **窗口管理** | 34 个 Rectangle 风格动作：半屏/四分之一/三分、尺寸、微移、跨屏、全屏与空间 | 设置/热键 | `Features/WindowManagement/`（62 个文件：AX 窗口清单、布局、房间、空间切换） |
| **窗口布局与房间** | 保存“这些应用、这些尺寸、这个排布”的声明式布局；“房间”是命名的窗口集合 | `Create Window Layout`、`Switch Room` | `Features/WindowManagement/Model/` |
| **系统操作** | 锁屏、睡眠、重启、清空废纸篓、切换外观/蓝牙、静音、显示隐藏文件等 | 搜索命令 | `Features/SystemActions/` |
| **日历与会议** | 空面板顶部的加入卡片、菜单栏摘要、一键加入或自动加入 | `Join Next Meeting`、`My Schedule`、`Create Event` | `Features/Calendar/` |
| **相机** | 实时预览，可悬浮显示或用于拍照 | `Open Camera` | `Features/Camera/` |
| **Apple 快捷方式** | 搜索并运行“快捷指令”App 中的快捷方式 | 搜索命令 | `Features/AppleShortcuts/` |
| **导航** | 两个“把用户送到某处”的命令（不改变任何东西） | 由独立开关控制 | `Features/`（见 `docs/features/navigation.md`） |

要点：窗口管理大量依赖 `AXUIElement` 与 `CGEventTap`，因此它的决策部分（`WindowLayout`、`Room` 等 Model 类型、34 个动作的枚举）与执行部分（`WindowMover`、`SpaceSwitcher`）被明确分层；确认门放在 Coordinator，runner 保持纯净可测。

#### 五、扩展运行时

| 功能 | 作用 | 入口 | 主要路径 |
| --- | --- | --- | --- |
| **Raycast 扩展** | 原生运行 Raycast 扩展，渲染为 SwiftUI | 搜索扩展命令（`.extensionCommand`） | `Features/Extensions/`（78 个文件：JSC 桥接、存储、OAuth、菜单栏、表单/网格） |
| **Raycast 导入** | 读取 Raycast v2.x 的 `.rayconfig` 迁移配置 | `Import from Raycast` | `Features/Extensions/` + `Features/Backup/` |

要点：所有扩展相关视图、几何与尺寸常量都被约束在 `Features/Extensions/` 内（见第 11 节）；运行时的 `RaycastRuntime.generated.js` 由 `Scripts/raycast-runtime/build.mjs` 生成并提交进仓库，因此构建应用不需要 Node。

#### 六、数据、配置与辅助

| 功能 | 作用 | 入口 | 主要路径 |
| --- | --- | --- | --- |
| **设置外壳** | 侧边栏分栏、搜索、锚点定位、设置文件镜像；每个功能一块 `Settings/` 面板 | `Settings` | `Features/Settings/`（30 个文件） |
| **备份与导入** | 把自身数据导出为单个 `.gearmac` 文件并导入 | `Export Settings`、`Import Settings` | `Features/Backup/` |
| **卸载应用** | 删除应用及其残留（缓存、偏好、容器、保存状态） | `Uninstall Application`（`.uninstall`） | `Features/Uninstall/` |
| **听写（实验性）** | 全局快捷键录音，模型在会退出的 helper 内运行 | 设置 → 听写（默认关闭） | `Features/Dictation/` |
| **首次引导** | 权限与初始设置引导 | 首次启动 | `Features/Onboarding/` |

入口命令的穷举清单在 `Features/Launcher/Model/CommandID.swift`（`CommandID.Builtin`）；**哪个命令属于哪个设置分栏**由 `SettingsTab.ownedCommands` 唯一定义，不要靠嗅探入口 ID 重新推导。

---

## 13. 持久化与设置文件镜像

### 13.1 存储位置

| 位置 | 内容 | 载体 |
| --- | --- | --- |
| `AppPaths.applicationSupport()` | 业务数据库、笔记、片段、扩展、布局、聊天历史 | 文件 / SQLite |
| `AppPaths.caches()` | 图标、缩略图、更新检查、汇率缓存 | 文件 |
| Keychain | 扩展 OAuth 令牌、AI/CLI 密钥 | `KeychainSecretStore` |
| `UserDefaults` | 用户偏好、当前笔记、窗口级状态 | `AppSettings` |
| SQLite | 剪贴板历史及其文本索引 | `ClipboardStore` |

### 13.2 设置的双轨

设置有两个来源，这是架构上必须理解的一点：

1. **`UserDefaults` 轨**：`AppSettingsKey` 是 `AppSettings` 所有 UserDefaults 键的穷举清单；`AppSettings` 负责加载、默认值与写回。
2. **`settings.json` 镜像轨**（可选）：`SettingsFileRepository` 把设置镜像到 JSON，由 `SettingsFileSchema` 提供绑定。**新增一个偏好也必须新增一个 `SettingsFileKey` 及其绑定，否则穷举 switch 会让构建失败直到绑定完成。**

这条设计的深意在于安全边界：**授予能力的开关绝不通过备份或 `settings.json` 传递**。典型例子是 `snippetsEnabled` 被排除在设置备份覆盖之外，这样一次导入无法在用户不知情的情况下授予“键盘监听”能力。

设置变更的重投影集中在 `AppCore.observeFeatureSwitches()`：约 30 个 `track(...)` 调用，每个都声明“读哪些字段”与“变化时重投影什么”。因为 `settings.json` 可以在没有任何设置面板打开时改变设置，所以这些重投影不能只写在面板的 `onChange` 里。

---

## 14. 生成文件与脚本

以下产物**由脚本生成，绝不手工编辑**：

| 产物 | 生成命令 |
| --- | --- |
| `Features/Emoji/Model/EmojiData.generated.swift` | `node Scripts/gen-emoji.js` |
| `Resources/EmojiKeywords/`（9 种语言） | `node Scripts/gen-emoji.js` |
| `Features/Calculator/Model/CurrencyData.generated.swift` | `node Scripts/gen-currencies.js` |
| `Features/Calculator/Model/CountryZoneData.generated.swift` | `node Scripts/gen-countries.js` |
| `Resources/RaycastRuntime.generated.js` | `Scripts/raycast-runtime/build.mjs` |

`Scripts/` 覆盖全部可执行脚本：`run-tests.sh`、`lint.sh`、`format.sh`、`build-dmg.sh`、`release-notes.sh`、`verify-signature.sh`、`sync-lsp.sh`、三个数据生成器，以及 `raycast-runtime/` 子目录。

规则的核心是：**改数据先改脚本、再跑脚本，不直接编辑产物。**

---

## 15. 测试架构：harness 而非 XCTest

这是一个**没有 XCTest target** 的项目。测试是 106 个独立 Swift harness，每个一个文件，位于 `Tests/`。

机制（`Scripts/run-tests.sh`）：

- 每个 harness 用 `swiftc -swift-version 6 <opt> … Tests/<name>.swift -o …` **编译被守护的产品源码 + harness 自身**，然后运行；
- 编译失败 = “决策泄漏出了纯层”的信号，因为这正是 harness 无法编译的唯一主因；
- 并行执行，用 `.running` / `.failed` 标记文件通信；
- macOS 没有 `timeout`，因此 worker 轮询，卡死的 harness 会超时失败而不是拖垮套件；
- 脚本注释明确警告：**绝不能用 `&&` 连接编译与运行**，因为 `set -e` 会忽略非最终 AND-OR 列表成员的失败——CI 曾因此在某个 harness 自 phase 10 起就编译不过时仍报告成功。

这种“harness 编译产品源码”的模式，是第 5 节所述边界强制机制的基础设施：它把架构约束变成了 CI 上的编译结果。

---

## 16. 构建、渠道与签名

### 16.1 三个 target

| target | 类型 | 用途 |
| --- | --- | --- |
| `GearMac` | application | 主应用 |
| `ClipboardTextHelper` | tool | 剪贴板文本识别进程 |
| `DictationHelper` | application | 听写模型进程（`LSUIElement`） |

### 16.2 渠道隔离

**Debug 是独立渠道**：`PRODUCT_NAME = GearMac-dev`、`PRODUCT_BUNDLE_IDENTIFIER = com.gearmac.app.dev`。这意味着本地运行的构建拥有**自己的偏好、缓存、TCC 授权和登录项**，不会继承甚至破坏已安装版本的状态。注释明确指出：**任何新持久化的东西都必须以 `Bundle.main.bundleIdentifier` 为键。**

Debug 与 Release 在签名上也有区别：Release 启用 `ENABLE_HARDENED_RUNTIME`、开启部署后处理与死代码剥离；注释解释了为什么硬化运行时只在 Release 开——库验证会拒绝 Debug 的 `.debug.dylib`（其 team 永远不匹配）。

`project.yml` 还特意为两个 helper 固定了 `EXECUTABLE_NAME` 与 `PRODUCT_MODULE_NAME`，因为 `release.yml` 会在 `xcodebuild` 命令行传 `PRODUCT_NAME`，这会命中每个 target：不固定的话，渠道构建会重命名 `ClipboardTextWorker` 寻找的可执行文件，并给模块名带上空格。

### 16.3 签名

使用稳定的自签名身份 `GearMac Self-Signed`（见 `docs/signing.md`），目的是**重建后 macOS 仍保留辅助功能授权**。这是直接分发路线的必要补充：自签名 + Homebrew 清除 quarantine 标记，是这类工具被用户接受的实际方式。

---

## 17. 架构评价：设计取舍与风险点

### 17.1 设计上最值得借鉴的地方

1. **用编译强制分层边界**。`Model/` 禁 import AppKit/SwiftUI 不是文档口号，而是由 harness 编译产品源码来兑现；边界漂移会立即变成编译失败。这是把“架构规矩”变成“工程事实”的教科书做法。
2. **单一组合根**。`AppCore` 是唯一单例，启动序列一眼可读，新增状态只有一条路径。避免了“十个功能各自持单例”的失控。
3. **决策与执行的物理分离**。确认门在 Coordinator、纯规则在 Model，使破坏性操作既无法绕过，又能被 harness 编译验证。
4. **进程边界即资源边界**。Vision/PDFKit/模型适配器都放在会退出的 helper 里，直接减少主进程的内存峰值与泄漏面。
5. **扩展运行时“盒子化”**。第三方代码绝不渗透进启动器表面，为隔离宁可容忍局部重复。这是安全边界优先于 DRY 的罕见且正确的取舍。
6. **能力开关不入备份**。`snippetsEnabled` 这类开关被排除在备份之外，从数据流上防止“导入即授予能力”。

### 17.2 这套架构带来的成本

- **强耦合于当前 macOS**。latest-only 意味着无法在旧系统上分发，也无法靠兼容层换取时间；一旦某个现代 API 行为回归，项目没有缓冲。这是刻意的战略选择，但也是最大的单点依赖。
- **组合根膨胀风险**。`AppCore.start()` 已经很长（一个屏幕的体量），协调器数量达 34。新增功能时，组合根会持续变长。目前靠“每个协调器单一职责 + 闭包接线”控制，但这是需要持续警惕的复杂度热点。
- **视图中键盘处理的复杂度**。`RootPaletteView` 的 key handler 链已经长到需要拆分才能通过类型检查。这在一定程度上是把交互状态机的复杂度留在了视图层；好消息是核心决策已抽成可测的 `Palette*Action` 解析函数。
- **文档与源码的数量容易不同步**。`architecture.md` 写的是“39 个 observable / 21 个 coordinator”，而当前源码实测为 79 处 `@Observable` / 34 个 Coordinator。这类数字天然会腐化；本文因此标注了实测口径。建议文档只描述结构与规则，把精确数字放到自动生成的统计里。
- **`NSAlert` 孤例**。`ExtensionManager.openWithPicker` 是唯一突破“自绘对话框”规则的地方。可接受，但应作为已知例外记录，避免被当成先例。

### 17.3 适合继续演进的方向（基于源码观察）

- 把 `AppCore.start()` 拆成按域组织的小节函数或启动阶段类型，可降低组合根的长度而不改变所有权。
- 对 `RootPaletteView` 的 key handler，可考虑进一步把“模式 × 按键 → 行为”的决策下沉为纯类型，视图只做转发。
- 为文档中的可计量事实引入生成或校验，减少人工维护的数字漂移。

---

## 18. 维护者阅读路径

1. 先读本文件与 `docs/architecture.md`，建立所有权与依赖方向的心智模型；
2. 读 `AGENTS.md` 的 “Non-negotiables”，它们是提交前必须遵守的硬约束；
3. 从 `AppCore.start()` 跟踪服务创建、协调器接线与窗口呈现；
4. 修改某功能前，先读 `docs/features/<功能>.md` 的 `## Invariants`；
5. 改动设置时同步检查 `AppSettingsKey`、`SettingsFileSchema`、备份覆盖与 Debug/Release 持久化边界；
6. 改动 UI 时只使用 `DesignSystem/Theme.swift` 的令牌与功能自身的布局常量；
7. 改动数据先改 `Scripts/` 中的生成脚本，再运行脚本，不直接编辑生成产物；
8. 完成前跑 `./Scripts/run-tests.sh`、确认 Debug 无新 warning、跑 `./Scripts/lint.sh`，并修正任何被改动弄错的文档。

---

## 19. 中文注释规范与标注范围

本节记录本次全量中文注释标注的规范、范围与校验结果，供后续维护沿用同一套约定。

### 19.1 注释规范（约定）

每个源文件顶部保留/写入 1–3 行中文职责说明，格式为：

```text
// 文件职责：<该文件实际做什么>。
// 分层：<Model/Service/UI/Settings/Coordinator；关键不变量>。
```

- 已有英文 `//`、`///` 注释翻译为简体中文，保留代码标识符、API 名与专有名词（如 `@MainActor`、`NSWindow`、`Sendable`）。
- 为没有注释的关键类型（`struct`/`class`/`enum`/`actor`/`protocol`）与关键函数、初始化器、计算属性补充一句中文 `///` 说明；过于显然的转发属性从简。
- 字符串字面量、日志/UI/错误文案、`// MARK:`、`#if/#available`、`// swiftlint` 等指令性注释一律不改动。

### 19.2 标注范围（实测）

| 范围 | 文件数 | 说明 |
| --- | --- | --- |
| `GearMac//` Swift 源码 | 780 | 应用全部 Swift 源码（App、DesignSystem、Platform、Palette、Windows、Features 全部分层） |
| `Tests/` Swift harness | 104 | 独立测试 harness（无 XCTest） |
| Swift 小计 | 884 | 全部含中文注释 |
| `Scripts/` JS / MJS / Shell | 38 | 数据生成器、Raycast 运行时源码、构建与发布脚本 |
| `website/` Next.js（TS/TSX/MJS） | 67 | 官网组件、数据与 Worker |
| 配置文件 | 24 | `project.yml`、`Info.plist`×2、`GearMac.entitlements`、`.swiftlint.yml`、`.coderabbit.yaml`、`.github/**`（workflows、ISSUE_TEMPLATE、FUNDING）、`.vscode/**`、`website/tsconfig.json`、`website/wrangler.jsonc`、`.dev.vars.example` 等 |

全量 diff 规模：`1011 files changed, +16239 −8351`。

### 19.3 明确不标注的文件（有意排除）

| 文件 / 类别 | 原因 |
| --- | --- |
| `*.generated.swift`（EmojiData、CurrencyData、CountryZoneData） | 生成产物，禁止手改；说明留在生成脚本中 |
| `Resources/RaycastRuntime.generated.js`、`Scripts/raycast-runtime/src/api/enums.generated.js` | 同上 |
| `Resources/EmojiKeywords/*`（9 种语言词表） | 生成数据 |
| 严格 JSON：`website/package.json`、`package-lock.json`、`pnpm-lock.yaml`、`Scripts/raycast-runtime/package.json`、`Assets.xcassets/**/Contents.json`、`gearmac.icon/icon.json`、`.oxlintrc.json` | JSON 语法不支持注释，加注释会破坏文件；其用途已在本文与生成脚本中说明 |
| `.swift-format` | JSON 格式配置，不支持注释 |
| `next-env.d.ts` | Next.js 自动生成、文件头自带“不要编辑” |

### 19.4 校验方法

因为要求“不改变代码逻辑”，本次用三重校验保证只改了注释：

1. **剥离注释后逐字节比对**：对每个文件，用字符串/正则字面量感知的词法剥离器去除 `//`、`/* */`（以及 YAML/Shell 的 `#`、XML 的 `<!-- -->`）后，与 `git HEAD` 版本对比；除注释外无任何差异。
2. **行级代码前缀比对**：对每个改动行，比较 `//` 之前的代码前缀，确认尾随注释只改了文本。
3. **语法与测试**：884 个 Swift 文件全部通过 `swiftc -parse -swift-version 6`；`./Scripts/lint.sh` 退出码 0（lint-clean，仅剩余既有 warning 与中文长注释触发的 `line_length` warning）；`./Scripts/run-tests.sh` 全部 **94 个 harness 通过**。

### 19.5 已知取舍

- 少数 `// MARK:` 与 MIT 归属声明保留英文原文（指令性/版权内容）。
- 测试 harness 内嵌的多行字符串（如 `ext-test.swift` 里的 JS 夹具）中的英文注释属字符串字面量，未改动。
- 中文职责说明较长，部分行触发 SwiftLint 的 `line_length` warning（仅警告、不阻塞）；如需消除，可按 100 字符上限折行。
- `Tests/` 与部分脚本的“分层”一栏按语义就近写作「测试 harness」「脚本」，未强行归入 Model/Service/UI 枚举。

---

> 本文相关源码入口：`GearMac//App/AppCore.swift`、`GearMac//App/AppDelegate.swift`、`GearMac//App/GearMacApp.swift`、`GearMac//Palette/PaletteScreen.swift`、`GearMac//Palette/PaletteWindowController.swift`、`GearMac//Palette/RootPaletteView.swift`、`project.yml`、`GearMac//GearMac.entitlements`、`Scripts/run-tests.sh`。

