// 文件职责：“从 Raycast 迁移过来”区块的文案与可保留的设置项清单。
// 分层：Model（静态数据）；步骤对应真实的导入流程（Settings → Backup → Raycast Export），
// transfers 与应用的 RaycastImportOptions 严格一致，不要添加导入器无法携带的项。

export const migration = {
  title: "Bring your Raycast setup.",
  intro:
    "GearMac reads Raycast's .rayconfig export. Choose the file, enter its passphrase, and your shortcuts, favorites and snippets come with it.",
  // 提前声明而不是只写在文档里：1.x 文件唯一不能导入的东西，
  // 等导入到一半才发现是最糟的结果。
  requirement: {
    title: "Raycast v2.0 and newer only",
    body: "GearMac reads .rayconfig files from Raycast v2.0 and later. Support for Raycast v1.x files was removed in GearMac v0.10.5.",
  },
  steps: [
    {
      title: "Export from Raycast",
      body: "Export your settings and data, and keep the passphrase you set.",
    },
    {
      title: "Open Settings → Backup",
      body: "Choose the file and enter the passphrase. If the passphrase is wrong, GearMac says so.",
    },
    {
      title: "Choose what to import",
      body: "Import everything, or only the parts you want.",
    },
    {
      title: "Quit and reopen GearMac",
      body: "Quit from the menu bar icon, because closing Settings isn't enough. Everything is in place after the restart.",
    },
  ],
  // 必须与 Features/Backup/Model/RaycastImport.swift 中的 RaycastImportOptions 保持一致。
  transfers: [
    "Shortcuts",
    "Favorites",
    "Clipboard history",
    "Snippets",
    "Quicklinks",
    "Aliases",
    "Emoji skin tone",
    "Compact mode",
    "Pop to root",
    "Launch at login",
    "Menu-bar preference",
  ],
} as const;
