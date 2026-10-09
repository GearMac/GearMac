# GearMac 架构与核心功能说明

> 本文根据当前源码、`project.yml`、应用清单和各功能目录整理。它是面向维护者的中文索引；具体不变量仍以对应功能文档和源码为准。

## 1. 产品边界

GearMac 是一个仅面向当前稳定版 macOS（26+）的原生菜单栏应用。它以 accessory app 运行，不在 Dock 中显示主图标，主要通过全局快捷键、菜单栏项目和浮动面板提供能力。

核心能力包括：

- 模糊应用启动器、收藏、别名、建议和最近使用排序；
- 全局快捷键、Hyper Key、双击修饰键和快捷键录制；
- 文本/图片/文件剪贴板历史、文本搜索、预览和粘贴；
- 内联计算器，支持数学、单位、日期时间、货币汇率；
- 笔记、片段、快速链接、自定义命令和文件搜索；
- 窗口切换、窗口布局、房间和系统操作；
- Emoji 选择器、日历/会议、相机、听写和 AI/Quick Actions；
- Raycast 扩展运行时、扩展安装、OAuth、菜单栏扩展和 JavaScriptCore 执行；
- 设置、备份/恢复、更新检查、引导页和支持窗口。

## 2. 启动与所有权

```text
GearMacApp (@main)
  └─ AppDelegate
      └─ AppCore.shared.start()
          ├─ 创建 AppSettings 与所有长期 Store/Manager/Session
          ├─ 创建各功能 Coordinator
          ├─ 注册快捷键、监听器、文件监视器和菜单栏状态
          ├─ 恢复外观、设置文件、笔记选择和窗口状态
          └─ 准备 Palette、Settings、Notes、AI Chat、HUD/Dialog 窗口
```

`AppCore` 是唯一的长期状态所有者。功能视图通过 `@Environment` 找到 Coordinator；视图不直接修改其他功能的 Store。新增长期状态必须放在 `AppCore` 并在 `start()` 中接线，不能再创建第二个全局容器。

`AppDelegate` 负责 AppKit 生命周期：启动、打开 URL、终止前清理 Hyper Key/听写/笔记，以及 Dock 触发的关闭窗口语义。`GearMacApp` 只声明两个 `MenuBarExtra`（GearMac 自身和日历），其他窗口由 AppKit Controller 管理。

## 3. 分层与依赖方向

```text
Model（纯决策）
   ↓
Service（文件、网络、AppKit、AX、事件、进程等副作用）
   ↓
Observable Store / Session / State（@MainActor）
   ↓
Coordinator + SwiftUI/AppKit View
```

### Model

`GearMac//Features/*/Model/` 只允许 Foundation（以及数据确实需要的 SQLite3/CoreGraphics），所有时间、文件路径、主目录、汇率等环境事实都通过参数注入。这里放搜索排序、计算器、窗口布局、备份格式、设置文件格式等可独立决定的规则。

### Service

Service 层执行副作用：`AXUIElement`、`CGEventTap`、`NSWorkspace`、`URLSession`、`FileManager`、CoreAudio、进程和网络请求都应位于此层。网络功能使用私有 `.ephemeral` session，关闭 URL cache；重 IO 使用 `Task.detached` 驱动的 `nonisolated` 函数。

### Observable 状态

项目使用 Swift Observation（`@Observable`），不使用 `ObservableObject`/`@Published`。状态类型默认 `@MainActor`，视图通过环境读取。缓存和懒加载协作者使用 `@ObservationIgnored`，避免把缓存填充误当成界面依赖。

### View 与 Coordinator

View 只负责声明界面和转发用户意图；Coordinator 负责把用户操作编排为 Store/Service 调用、确认弹窗和窗口动作。确认逻辑在 Coordinator，不在 runner 中，这样纯规则仍可由 harness 编译。

## 4. 窗口与交互表面

| 表面 | 所有者 | 作用 |
| --- | --- | --- |
| 命令面板 | `PaletteWindowController` | Borderless `NSPanel`，在紧凑输入条与完整启动器之间切换 |
| 设置/引导 | `SettingsCoordinator` / `OnboardingCoordinator` | 标题窗口，承载 SwiftUI 设置页 |
| 笔记 | `NotesWindowController` | 持久显示、Markdown 渲染、TextKit 2 编辑 |
| AI Chat | `AIChatCoordinator` | 侧边栏聊天列表与对话窗口；会话状态属于 `AppCore` |
| Dialog | `DialogController` | 确认、失败报告、输入请求；一次只显示一个 |
| HUD | `HUDPresenter` | 消息和音量反馈，自动消失、淡出、串行展示 |
| 相机 | `CameraSession` + 两个 Coordinator | 预览/拍照与会议 join 共用会话 |

项目禁止 `NSAlert` 和系统 popover，所有询问必须走 Dialog，所有报告走 HUD。

## 5. 功能目录地图

| 目录 | 核心职责 |
| --- | --- |
| `Launcher` | App 索引、模糊搜索、收藏、可见性、别名、排序 |
| `Palette` | 面板、屏幕栈、输入、行索引和各屏幕切换 |
| `HotKeys` | Carbon 全局快捷键、Hyper Key、修饰键监听 |
| `Clipboard` | 剪贴板采集、SQLite 历史、文本索引、预览、粘贴 |
| `Calculator` | 词法/表达式解析、单位、日期、货币和历史 |
| `Extensions` | Raycast manifest、运行时、扩展存储、OAuth、菜单栏 UI |
| `AI` / `MCP` / `QuickActions` | 模型连接、工具调用、MCP、文本改写/翻译/总结 |
| `Dictation` | 麦克风采集、模型 helper、转写、插入和音量恢复 |
| `WindowManagement` / `WindowSwitcher` | AX 窗口清单、布局、房间、空间切换和窗口轮换 |
| `Notes` / `Snippets` / `Quicklinks` | 本地 Markdown、片段关键字监听、链接启动 |
| `Calendar` / `Camera` | 日历读取、会议链接、自动加入、相机预览和拍照 |
| `Backup` / `Settings` / `Updates` | 备份恢复、设置文件镜像、更新检查与安装 |
| `DesignSystem` / `Platform` | 主题令牌、滚动/控件基础和系统能力适配 |

## 6. 配置与持久化

### 构建配置

`project.yml` 是 XcodeGen 的唯一项目源文件，生成 `GearMac.xcodeproj`。部署目标为 macOS 26，Swift 6，严格并发检查开启。项目包含三个 target：主应用、剪贴板文本 helper、听写 helper。Debug 使用 `com.gearmac.app.dev` 和独立产品名，因此不会污染稳定版的偏好、缓存、TCC 授权和登录项。

### 应用清单与权限

- `GearMac//Info.plist`：bundle 标识、URL scheme、备份文件 UTI、`LSUIElement` 和相机/麦克风/日历/自动化/提醒事项/蓝牙用途说明。
- `GearMac//GearMac.entitlements`：关闭 sandbox，允许 JavaScriptCore JIT、Apple Events、相机、音频输入和日历。
- `Features/Dictation/Helper/Info.plist`：听写 helper 的无 Dock 图标配置和通道化名称。

### 用户设置

`AppSettingsKey` 是 `AppSettings` 所有 UserDefaults 键的穷举清单；`AppSettings` 负责加载、默认值和写回。新增设置必须同时加入键枚举、默认值、属性和设置文件绑定。可选的 `settings.json` 由 `SettingsFileRepository` 镜像，导入时不能授予能力型开关；例如 `snippetsEnabled` 不进入备份覆盖范围。

其他持久化位置包括：

- `AppPaths.applicationSupport()`：业务数据库、笔记、片段、扩展和布局；
- `AppPaths.caches()`：图标、缩略图、更新检查和汇率缓存；
- Keychain：扩展 OAuth 和 AI/CLI 密钥；
- `UserDefaults`：用户偏好、当前笔记和窗口级状态；
- SQLite：剪贴板历史及其索引。

## 7. 进程边界与并发

剪贴板文本识别和听写模型在嵌入的 helper 进程执行。主进程只负责 UI、权限、音频采集和管道通信；helper 不访问数据库、剪贴板或设置。这样可以限制 Vision、PDFKit 和模型内存的生命周期。

Swift 6 数据竞争是编译错误。主线程状态集中在 `@MainActor`；跨 actor 的模型必须 `Sendable`；重 IO 使用结构化并发和 `Task.detached`。Carbon 指针在进入 actor 前解码为普通值，通知观察通过 `NotificationToken` RAII 管理。

## 8. 生成文件与维护边界

以下文件由脚本生成，不能手工编辑：

- `EmojiData.generated.swift`、`Resources/EmojiKeywords/`：`node Scripts/gen-emoji.js`；
- `CurrencyData.generated.swift`：`node Scripts/gen-currencies.js`；
- `CountryZoneData.generated.swift`：`node Scripts/gen-countries.js`；
- `Resources/RaycastRuntime.generated.js`：`Scripts/raycast-runtime/build.mjs`。

Extensions 的布局、菜单、行和尺寸只属于 `Features/Extensions`；不能为了复用把它们提升到 DesignSystem。`EdgeDissolve.swift` 与 `ThinScrollbar.swift` 是视觉校准文件，除非任务明确要求，不应修改。

## 9. 维护者阅读顺序

1. 先读本文和 `docs/architecture.md`，确定所有权与依赖方向；
2. 再读目标功能目录下的文档和 `Model/` 不变量；
3. 从 `AppCore.start()` 追踪服务创建、Coordinator 接线和窗口呈现；
4. 修改设置时同步检查 `AppSettingsKey`、`SettingsFileSchema`、备份覆盖和 Debug/Release 持久化边界；
5. 修改 UI 时只使用 `DesignSystem/Theme.swift` 和功能自身的布局常量；
6. 生成数据先改脚本，再运行脚本，不直接编辑生成产物。

