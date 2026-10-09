#!/usr/bin/env node
// 文件职责：校验 Settings 搜索目录 SettingsSearchCatalog 里的每个条目都能落到一个真实存在的 section/row 上。
// 分层：脚本（由 ./Scripts/lint.sh 调用）；只对 Swift 源码做静态文本匹配，不编译也不运行 Swift。
//
// 每个 Settings 搜索结果都必须有可落点。
//
// `Form` 无法被询问它包含哪些 section 或 row，所以 `SettingsSearchCatalog` 是手写的，其目标以文本方式与
// 各面板对应。一个无处可滚动到的条目依旧能编译、读起来也正常，只在运行时失败 —— 表现为结果导航过去后
// 停在那里，什么也不滚动、什么也不高亮。
//
// 用法：node Scripts/check-settings-search.js   （由 ./Scripts/lint.sh 运行）
"use strict";

const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..");
const ANCHORS = "GearMac//Features/Settings/SettingsAnchor.swift";
const CATALOG = "GearMac//Features/Settings/SettingsSearchCatalog.swift";

/// 递归收集 dir 下所有 .swift 文件的完整路径。
function swiftSources(dir, found = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) swiftSources(full, found);
    else if (entry.name.endsWith(".swift")) found.push(full);
  }
  return found;
}

const anchorSource = fs.readFileSync(path.join(ROOT, ANCHORS), "utf8");
const catalog = fs.readFileSync(path.join(ROOT, CATALOG), "utf8");
const source = swiftSources(path.join(ROOT, "GearMac"))
  .map((f) => fs.readFileSync(f, "utf8"))
  .join("\n");

// 锚点标识符 → 其 title 文案，供「启动器分类开关」那条规则推导标题时使用。
const anchorTitles = new Map();
for (const m of anchorSource.matchAll(
  /static let (\w+) = Self\(\s*tab: \.\w+, title: "([^"]+)"\)/g
)) {
  anchorTitles.set(m[1], m[2]);
}

const problems = [];

// 1. 每个锚点都必须被某个 section 声明。
for (const anchor of anchorTitles.keys()) {
  const claimed =
    source.includes(`SettingsSectionHeader(.${anchor})`) ||
    source.includes(`SettingsSectionHeader(anchor: .${anchor})`) ||
    source.includes(`settingsAnchor(.${anchor})`) ||
    source.includes(`anchor: .${anchor}`);
  if (!claimed) problems.push(`anchor .${anchor} — no Section declares it`);
}

// 2. 每个行条目都必须在某一行上被标记。
for (const m of catalog.matchAll(/\.init\(\s*\.(\w+),\s*"((?:[^"\\]|\\.)*)"/g)) {
  const [, anchor, title] = m;
  // 行标题现在多为本地化表达式（`settings.text(...)`），因此只按锚点匹配；锚点才是真正的落点。
  const marked =
    new RegExp(`SettingsRowTitle\\(\\s*\\.${anchor},`).test(source) ||
    new RegExp(`SettingsFeatureToggleLabel\\(\\s*anchor: \\.${anchor}\\b`).test(source) ||
    // `SettingsRow` 会用它自己的 title 渲染这个 pill。
    new RegExp(`SettingsRow\\(\\s*title: [^\\n]*[\\s\\S]{0,400}?anchor: \\.${anchor}\\b`).test(source) ||
    // 功能面板的主开关，由 `FeatureSwitchSection` 渲染。
    new RegExp(`anchor: \\.${anchor},\\s*\\n\\s*enableTitle:`).test(source) ||
    // 启动器分类的开关，其 title 由 `LauncherItemsSection` 推导得出。
    title === `Enable ${anchorTitles.get(anchor) ?? ""}`;
  if (!marked) problems.push(`row “${title}” (.${anchor}) — no SettingsRowTitle marks it`);
}

if (problems.length > 0) {
  console.error("\n✗ Settings search targets with nothing to land on:");
  for (const p of problems) console.error(`  ${p}`);
  console.error("  Mark the row with SettingsRowTitle, or make the entry a `group:` one.");
  process.exit(1);
}
