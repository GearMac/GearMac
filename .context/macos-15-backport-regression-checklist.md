# Zappale macOS 15.0 降级适配 — 实机回归清单

> 分支 `backport-macos-15`（7 个 commit，f3ea4ad..e4c594a）。构建产物已验证：
> `LSMinimumSystemVersion=15.0`（主 app + Dictation helper），FoundationModels 弱链接（LC_LOAD_WEAK_DYLIB）。
> 实机验证前请从该分支构建 DMG 或直接拷贝 Release 产物。

## macOS 15（新增能力验证，需真机或 VM）

1. **安装与启动**：拖入 /Applications 双击启动，不弹版本警告，无崩溃报告
2. **主面板**：Palette 弹出、NSVisualEffectView 回落背景观感可接受（不佳则调 `GlassEffectView.fallbackView()` 的 material，只改一处）
3. **HUD**：音量/消息 HUD 正常显示
4. **Apple Intelligence 全入口不展示**：模型选择器无 On-device 分组；设置 → AI → Providers 左侧无 "On This Mac" 节；AI 主设置页无端侧路由提示文案；首次启动默认模型回落到其他路由或提示选择
5. **翻译 Quick Action 不展示**：内置动作列表、启动器命令、设置页均无 Translate；其余四个内置动作（修语法/改写/总结/判定）正常
6. **MCP OAuth 登录**：添加需要 OAuth 的 MCP 服务器，浏览器回调后能拿到授权码（此路径走 NWListener，与 26 不同的实现）
7. **其余 AI 路由正常**：Codex/Claude/Grok/OpenCode/Cursor/API 任选一个可正常发起对话
8. **听写 / 剪贴板**：Dictation helper 启动推理正常；剪贴板文本/图片/文件历史正常
9. **Notes 撤销/重做**：编辑笔记后 Cmd+Z / Cmd+Shift+Z 触发渲染刷新（此路径换了跨版本通知 API）
10. **计算器地区格式**：系统切换单位/分隔符后无需重启即生效（同上，换了通知 API）
11. **应用重启（登录项/检查更新触发的 restart）**：能等待旧实例退出再拉起新实例（换了 NSWorkspace 通知）
12. **TCC 授权**：麦克风/相机/日历/蓝牙首次授权弹窗正常

## macOS 26/27（零回归验证）

1. 主面板/HUD/各弹层 Liquid Glass 观感与改造前一致（折射、自适应、悬停高亮）；聊天的建议 chip 与引用按钮为 Glass 按钮样式
2. Apple Intelligence 可正常发起端侧对话（guardrails 语义不变）；模型未就绪时设置页照旧展示状态文案
3. Quick Actions 选 Apple Intelligence 的动作正常；翻译动作在列表中正常展示
4. MCP OAuth 登录走 NetworkListener 路径正常（mcp-oauth-test 已在 95/95 通过中覆盖）

## 若 macOS 15 出现 dyld 崩溃

查看 `~/Library/Logs/DiagnosticReports/` 下 crash report 的 `dyld` 段，定位缺失符号所属框架，回到对应文件补 `#available` 分支。

## 判断点总账（最终版，供后续维护对照）

运行时 `#available(macOS 26.0, *)` 共 8 处：

| 位置 | 作用域 |
|------|--------|
| `Theme.frosted` | 交互玻璃封装（1 使用方） |
| `Theme.glassSurface` | 静态玻璃封装（14 使用方） |
| `Theme.glassButtonStyle` | 玻璃按钮封装（2 使用方） |
| `GlassEffectView.makeNSView` | 面板背景封装（8 使用方） |
| `BuiltInQuickAction.isAvailable` | 翻译功能域单点（3 展示点复用） |
| `TextTranslator.translate` | 翻译功能域防御兜底（拦截绕过菜单的触发） |
| `AppleIntelligenceProvider.status` | 端侧路由单点（全链路复用） |
| `AppleIntelligenceProvider.stream` | 端侧路由编译器强制守卫（实现体引用 26 类型） |
| `MCPOAuthListener.start` | MCP OAuth 双路径分派（老 NWListener 在 26 被系统拒绝） |

编译器标注 `@available(macOS 26.0, *)` 6 处（AppleIntelligenceProvider 内 26-only 成员 + MCPOAuthListener 26 路径成员），非运行时判断。

换用跨版本等价 API（零判断点）：NotificationCenter forName 三处、posix_spawn addchdir_np、UndoManager/NSWorkspace/NSLocale 老通知名。
