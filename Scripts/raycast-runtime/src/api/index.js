// 文件职责：组装扩展通过 `require("@raycast/api")` 拿到的顶层模块，把组件、枚举、系统 API 与 OAuth 合并成单一命名空间。
// 分层：运行时 shim 入口（JS）；只做聚合与别名映射，实现分别在 components.js / enums.generated.js / system.js / oauth.js。

import { Action, ActionPanel, Detail, Form, Grid, List, MenuBarExtra, Navigation, setActionEffects, useNavigation } from "./components.js";
import * as enums from "./enums.generated.js";
import * as system from "./system.js";
import { PKCEClient, TokenSet } from "./oauth.js";

const { nestedEnums, ...flatEnums } = enums;

Form.DatePicker.Type = flatEnums.DatePickerType;
Action.PickDate.Type = flatEnums.DatePickerType;
Grid.Fit = flatEnums.GridFit;
Grid.Inset = flatEnums.GridInset;
Grid.ItemSize = flatEnums.GridItemSize;
Grid.AspectRatio = flatEnums.GridAspectRatio;
Action.Style = flatEnums.ActionStyle;

// 便捷 action 通过系统 API 执行副作用，而不是各自重复实现一份。
setActionEffects({
  copy: async ({ content, concealed }) => {
    await system.Clipboard.copy(content, { concealed });
    await system.closeMainWindow();
    await system.showHUD("Copied to Clipboard");
  },
  paste: async ({ content }) => {
    await system.Clipboard.paste(content);
  },
  open: async ({ target, application }) => {
    await system.open(target, application);
    await system.closeMainWindow();
  },
  openWith: async ({ path }) => {
    await system.openWith(path);
  },
  showInFinder: async ({ path }) => {
    await system.showInFinder(path);
    await system.closeMainWindow();
  },
  trash: async ({ paths }) => {
    await system.trash(paths);
  },
  createSnippet: () => system.unsupported("Action.CreateSnippet"),
  createQuicklink: () => system.unsupported("Action.CreateQuicklink"),
  quickLook: () => system.unsupported("Action.ToggleQuickLook"),
  unsupported: (what) => system.unsupported(what),
});

const Image = { Mask: nestedEnums.Image.Mask };

const Alert = { ActionStyle: nestedEnums.Alert.ActionStyle };

const Keyboard = {
  Shortcut: {
    Common: {
      Copy: { modifiers: ["cmd", "shift"], key: "c" },
      CopyDeeplink: { modifiers: ["cmd", "shift"], key: "c" },
      CopyName: { modifiers: ["cmd", "shift"], key: "." },
      CopyPath: { modifiers: ["cmd", "shift"], key: "," },
      Save: { modifiers: ["cmd"], key: "s" },
      Duplicate: { modifiers: ["cmd"], key: "d" },
      Edit: { modifiers: ["cmd"], key: "e" },
      MoveDown: { modifiers: ["cmd", "shift"], key: "arrowDown" },
      MoveUp: { modifiers: ["cmd", "shift"], key: "arrowUp" },
      New: { modifiers: ["cmd"], key: "n" },
      Open: { modifiers: ["cmd"], key: "o" },
      OpenWith: { modifiers: ["cmd", "shift"], key: "o" },
      Pin: { modifiers: ["cmd", "shift"], key: "p" },
      Refresh: { modifiers: ["cmd"], key: "r" },
      Remove: { modifiers: ["ctrl"], key: "x" },
      RemoveAll: { modifiers: ["ctrl", "shift"], key: "x" },
      ToggleQuickLook: { modifiers: ["cmd"], key: "y" },
    },
  },
};

/// 生成 GearMac 尚未实现的那部分 API。它们存在的意义是：仅 import 了这些名字的扩展包仍能正常加载；
/// 一旦真正调用，会给出明确原因（而不是一个 TypeError）。
function rejectingNamespace(name, members) {
  const target = {};
  for (const member of members) target[member] = () => system.unsupported(`${name}.${member}`);
  return target;
}

const AI = {
  ...rejectingNamespace("AI", ["ask"]),
  Model: Object.freeze({}),
  Creativity: Object.freeze({}),
};

const OAuth = {
  RedirectMethod: nestedEnums.OAuth.RedirectMethod,
  PKCEClient,
  TokenSet,
};

const BrowserExtension = rejectingNamespace("BrowserExtension", ["getContent", "getTabs"]);

const WindowManagement = {
  DesktopType: nestedEnums.WindowManagement.DesktopType,
  ...rejectingNamespace("WindowManagement", ["getWindowsOnActiveDesktop", "getActiveWindow", "setWindowBounds", "getDesktops"]),
};

export const raycastApi = {
  // 组件
  List,
  Grid,
  Detail,
  Form,
  ActionPanel,
  Action,
  MenuBarExtra,
  Icon: flatEnums.Icon,
  Color: flatEnums.Color,
  Image,
  Keyboard,
  Alert,
  Toast: system.Toast,
  Cache: system.Cache,
  LaunchType: flatEnums.LaunchType,
  PopToRootType: flatEnums.PopToRootType,

  // 导航
  useNavigation,
  Navigation,

  // 反馈
  showToast: system.showToast,
  showHUD: system.showHUD,
  confirmAlert: system.confirmAlert,

  // 系统
  Clipboard: system.Clipboard,
  LocalStorage: system.LocalStorage,
  environment: system.environment,
  getPreferenceValues: system.getPreferenceValues,
  openExtensionPreferences: system.openExtensionPreferences,
  openCommandPreferences: system.openCommandPreferences,
  closeMainWindow: system.closeMainWindow,
  popToRoot: system.popToRoot,
  clearSearchBar: system.clearSearchBar,
  open: system.open,
  trash: system.trash,
  showInFinder: system.showInFinder,
  getApplications: system.getApplications,
  getDefaultApplication: system.getDefaultApplication,
  getFrontmostApplication: system.getFrontmostApplication,
  getSelectedText: system.getSelectedText,
  getSelectedFinderItems: system.getSelectedFinderItems,
  getFrontmostBrowserTab: system.getFrontmostBrowserTab,
  captureException: system.captureException,
  launchCommand: system.launchCommand,
  updateCommandMetadata: system.updateCommandMetadata,

  OAuth,

  // 未实现的命名空间
  AI,
  BrowserExtension,
  WindowManagement,

  // 已废弃的别名
  copyTextToClipboard: system.copyTextToClipboard,
  pasteText: system.pasteText,
  clearClipboard: system.clearClipboard,
  getLocalStorageItem: system.getLocalStorageItem,
  setLocalStorageItem: system.setLocalStorageItem,
  removeLocalStorageItem: system.removeLocalStorageItem,
  allLocalStorageItems: system.allLocalStorageItems,
  clearLocalStorage: system.clearLocalStorage,
  randomId: system.randomId,
  ActionPanelItem: Action,
  ActionPanelSection: ActionPanel.Section,
  ActionPanelSubmenu: ActionPanel.Submenu,
  CopyToClipboardAction: Action.CopyToClipboard,
  OpenInBrowserAction: Action.OpenInBrowser,
  OpenAction: Action.Open,
  PasteAction: Action.Paste,
  PushAction: Action.Push,
  ShowInFinderAction: Action.ShowInFinder,
  SubmitFormAction: Action.SubmitForm,
  TrashAction: Action.Trash,
  ImageMask: Image.Mask,
  ToastStyle: system.Toast.Style,
  AlertActionStyle: Alert.ActionStyle,
  FormTextField: Form.TextField,
  FormTextArea: Form.TextArea,
  FormCheckbox: Form.Checkbox,
  FormDatePicker: Form.DatePicker,
  FormDropdown: Form.Dropdown,
  FormDropdownItem: Form.Dropdown.Item,
  FormDropdownSection: Form.Dropdown.Section,
  FormSeparator: Form.Separator,
  FormTagPicker: Form.TagPicker,
  FormTagPickerItem: Form.TagPicker.Item,
};

// esbuild 编译出的扩展包在展开命名空间前会先探测该 interop 标记。
raycastApi.__esModule = true;
raycastApi.default = raycastApi;
