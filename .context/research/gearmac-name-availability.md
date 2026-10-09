# 「GearMac」名称可用性调研

调研时间：2026-10-09
目的：判断 GearMac 是否适合作为本 macOS App 的产品名（当前工程内部名为 Zappale，`project.yml` / bundle id 均为 `com.zappale`）。

## 一、核验结果（含来源）

| 维度 | 结果 | 证据来源 |
| --- | --- | --- |
| App Store 同名应用 | **无**。macSoftware 实体检索无 "GearMac"；全实体检索仅有 1 条无关的 "Gear MAX" | iTunes Search API |
| 域名（.com） | **未注册** | Verisign whois "No match" + RDAP `rdap.verisign.com` HTTP 404 |
| 域名（.net） | 未注册 | Verisign whois + RDAP 404 |
| 域名（.org） | 未注册 | whois.pir.org "Domain not found" |
| 域名（.io） | 未注册 | whois + RDAP 404 |
| 域名（.app / .dev） | 未注册 | Google Registry RDAP `pubapi.registry.google` HTTP 404 |
| 域名（.co） | 未注册 | whois.nic.co "DOMAIN NOT FOUND" |
| DNS 解析 | 上述域名均无 A 记录，与"未注册"一致 | dig |
| 全网搜索占用 | **几乎为零**。Bing 精确检索 `"GearMac"` 无任何真实命中，只回落到泛化的 "Mac 软件" 文章 | Bing（cn，精确短语模式） |
| GitHub | 存在组织 `github.com/GearMac`（**2026-10-09 创建、0 仓库**，疑为用户本人刚注册）；相关项目仅为无关的 `GearMachine`（Android 齿轮控件）等 | GitHub Search API |
| Homebrew | 无 `gearmac` / `zappale` 同名 cask（共 7788 个 cask） | formulae.brew.sh API |
| 商标（覆盖 CN/US/EU/JP 等） | 无 "GearMac" 商标。最接近：**GEARMACH** — 中国，第 9 类（软件/电子），北京捷尔迈科科技有限公司，2012-05-10 申请、2013-08-14 注册、**2023-08-13 到期**；另有一条罗马尼亚 GEARMACH（第 35/37 类，已失效） | TMview (TMDN/EUIPO) API |

## 二、名称评价

### 优点
- **语义直白**：Gear + Mac 直接表达"给 Mac 加装备/工具"，与现有 tagline "Gear up your Mac" 咬合。
- **易读易拼**：7 个字母、双音节，中英文语境都容易念写。
- **品牌窗口极好**：`.com` 及主流后缀全部可注册，且无同名 App、无搜索占用、无同名 Cask——这种"干净度"对一个新品牌是稀缺条件。
- **商标层面无在先完全相同的障碍**（见下）。

### 风险
- **"Mac" 是 Apple 商标**。Apple 的第三方商标指南原则上不鼓励在自有产品名中使用 Apple 商标；现实中大量 Mac 工具名使用（CleanMyMac、MacBooster、MacKeeper、MacUpdater、MacPilot 等），通常被容忍，但两点代价明确：一是 App Store 文案若暗示 Apple 出品/授权，审核可能拒；二是**名字被锁死在 macOS**，后续做 iOS / iPadOS / visionOS 版本时名字会很别扭。
- **描述性过强 → 商标显著性弱**。纯描述性名称在多数司法辖区难以取得强商标保护，也很难阻止他人使用相近的 "…Mac / Mac…" 命名；在搜索里会淹没在一堆 Mac 工具中。
- **近似商标 GEARMACH（中国，第 9 类软件）**：虽然已于 2023-08-13 到期，但读音与 GearMac 高度接近、且落在第 9 类。若计划在中国申请商标或面向中国销售，需要以 CNIPA 官方查询结果为准，评估是否构成近似障碍或异议风险。
- **可读性歧义**：连写 "gearmac" 存在 "Gear Mac / Gearmac" 的断词歧义，可能造成输入法和 SEO 上的分散。
- **联想干扰**：与 Samsung "Gear" 硬件、Gearbox、"Gears of War" 等有轻微联想竞争。

## 三、建议

1. **如果确定要用**：尽快在注册商处注册 `gearmac.com`（同时保护 `.app` / `.io` / `.dev`）——当前是空窗期，这是最容易随时间消失的机会。
2. **商标**：若面向中国或需要第 9 类保护，先做 CNIPA 官方检索（近似的 GEARMACH 已到期，需确认到期状态与是否构成障碍），必要时在美/中/欧同步提交第 9 类申请。描述性名称建议配合图形/Logo 组合商标来提高显著性。
3. **"Mac" 的处理方式（推荐做法）**：**产品名去掉 Mac**（例如仅用 "Gear"，或另取一个独有词），把 "for Mac" / "Gear up your Mac" 放在副标题和文案里。这样既保留语义，又规避 Apple 商标问题、并为跨平台留出空间。若坚持用 GearMac，则确保所有对外文案不暗示与 Apple 的关联。
4. **名字在 App Store Connect 是可预留资源**：`GearMac` 目前无占用，建议在定名前尽早在 App Store Connect 预留名称（该操作是全局的，跨 iOS/macOS）。
5. **重命名成本提示**：仓库内 `zappale` 出现在约 283 个文件中，涉及 bundle id（`com.zappale`）、签名/Team ID 锚定、Homebrew tap、文档与本地化 key。当前版本为 0.1.0（未发布），是改名成本最低的时机；一旦发布后改 bundle id 会丢失更新连续性。

## 四、一句话结论

**可用，且窗口期极佳（关键域名全空、无同名 App、无在先相同商标）；但它是一个"描述性强、商标弱、且带上 Apple 商标的 Mac 后缀"的名字——短期做 Mac 工具够用，长期想跨平台或做品牌护城河，建议去掉 "Mac" 或另取独有词。**
