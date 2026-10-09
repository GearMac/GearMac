// 文件职责：隐私区块的数据，包含统计数字、各功能默认开关状态与权限说明。
// 分层：Model（静态数据）；这里的每条主张都必须在文档中有出处（Getting started、
// Settings → Features、Permissions、Extensions、AI、Snippets、Calendar、Clipboard），不要新增无出处的说法。

import type { IconName } from "../components/ui/feature-icons";

// 隐私区块顶部的四个统计数字。
export const privacyStats = [
  { value: "0", label: "accounts" },
  { value: "0", label: "telemetry" },
  { value: "0", label: "dependencies" },
  { value: "<100 MB", label: "of memory" },
] as const;

// 某个功能的默认开关状态与说明。
export type DefaultSwitch = {
  icon: IconName;
  name: string;
  note: string;
  isOn: boolean;
};

// 对应 docs/reference/settings 中的 Features 表格：除剪贴板外全部默认关闭
// （Emoji 没有开关，不计入）。
export const defaultSwitches: DefaultSwitch[] = [
  {
    icon: "aiChat",
    name: "AI",
    note: "The chat command and its history file don't exist until you turn AI on.",
    isOn: false,
  },
  {
    icon: "extensions",
    name: "Extensions",
    note: "While off, no extension folder is read and no JavaScript engine runs.",
    isOn: false,
  },
  {
    icon: "snippets",
    name: "Snippets",
    note: "The only feature that reads what you type. Matching happens on your Mac.",
    isOn: false,
  },
  {
    icon: "calendar",
    name: "Calendar",
    note: "Tells you what it reads before macOS asks for access. Events stay on your Mac.",
    isOn: false,
  },
  {
    icon: "clipboard",
    name: "Clipboard history",
    note: "Stored on your Mac for 3 months. Ignores copies from Keychain Access and Passwords.",
    isOn: true,
  },
];

// 权限策略说明：只在功能首次需要时请求权限，绝不在启动时申请；
// 恢复设置备份也无法开启扩展或片段。
export const permissionNote =
  "GearMac asks for a permission only when a feature first needs it, never at launch. Restoring a settings backup can't turn on extensions or snippets.";
