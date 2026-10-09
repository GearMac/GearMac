// 文件职责：实现 @raycast/api 的组件层，把每个 Raycast 组件映射成宿主节点树供 Swift 侧渲染。
// 分层：运行时 shim（纯 JS，不依赖 Swift）；组件都是纯 React 函数组件，元素类型的 props 一律搬进 `__slot` 子节点，确保 reconciler 真正渲染、Swift 收到的是结构化数据。

import {
  createContext,
  createElement as h,
  useCallback,
  useContext,
  useEffect,
  useImperativeHandle,
  useMemo,
  useRef,
  useState,
} from "react";
import { SLOT_TYPE } from "../reconciler.js";
import { Icon, ActionStyle } from "./enums.generated.js";

/// `single: true` 表示该 slot 的父节点只接受单个节点，而不是节点列表。
function slot(name, element, single = true) {
  if (element === undefined || element === null || element === false) return null;
  return h(SLOT_TYPE, { key: `__slot_${name}`, name, single }, element);
}

/// 返回剔除指定 key 后的 props 浅拷贝，避免把已单独包成 slot 的子元素/动作重复传给宿主节点。
function omit(props, keys) {
  const out = {};
  for (const key of Object.keys(props)) if (!keys.includes(key)) out[key] = props[key];
  return out;
}

// ─── 导航 ───────────────────────────────────────────────────────────

const NavigationContext = createContext(null);

/// 读取当前导航栈的 push/pop 能力；不在 NavigationRoot 内时返回空实现。
export function useNavigation() {
  const navigation = useContext(NavigationContext);
  if (navigation) return navigation;
  // 无视图的 command 没有导航栈；此处让 push/pop 变成空操作，而不是直接崩溃。
  return { push: () => {}, pop: () => {} };
}

export const Navigation = { useNavigation };

/// 已挂载的导航根节点：所有被 push 的屏幕都保持挂载（这样 pop 回来时能恢复其状态），并只把栈顶
/// 标记为 active。Swift 渲染当前 active 的那个 `__screen`。`controls` 会被填入 push/pop，
/// 使会话可以直接响应 Escape 执行 pop，而不必经过某个已渲染的处理器。
export function NavigationRoot({ initial, onStackChange, controls }) {
  const [stack, setStack] = useState(() => [{ key: 0, element: initial }]);
  const nextKey = useRef(1);

  const push = useCallback(
    (element) => {
      setStack((current) => {
        const next = [...current, { key: nextKey.current++, element }];
        onStackChange?.(next.length);
        return next;
      });
    },
    [onStackChange],
  );

  const pop = useCallback(() => {
    setStack((current) => {
      if (current.length <= 1) return current;
      const next = current.slice(0, -1);
      onStackChange?.(next.length);
      return next;
    });
  }, [onStackChange]);

  const value = useMemo(() => ({ push, pop }), [push, pop]);
  if (controls) {
    controls.push = push;
    controls.pop = pop;
  }

  return h(
    NavigationContext.Provider,
    { value },
    stack.map((entry, index) =>
      h("__screen", { key: entry.key, active: index === stack.length - 1 }, entry.element),
    ),
  );
}

// ─── 表单状态 ───────────────────────────────────────────────────────

const FormContext = createContext(null);

/// 把字段注册到最近的 Form 上下文，使 Action.SubmitForm 能收集到完整表单值。
function useFormRegistration(id, value, setValue) {
  const form = useContext(FormContext);
  if (form && id) form.fields.set(id, { value, setValue });
  return form;
}

/// 返回字段的值：扩展传了受控 `value` prop 时用它，否则用组件内部的局部状态。
function useFieldValue(props, fallback) {
  const [local, setLocal] = useState(() => (props.value !== undefined ? props.value : props.defaultValue ?? fallback));
  const controlled = props.value !== undefined;
  const value = controlled ? props.value : local;
  const setValue = useCallback(
    (next) => {
      if (!controlled) setLocal(next);
    },
    [controlled],
  );
  useFormRegistration(props.id, value, setLocal);
  return [value, setValue];
}

/// React 19 把 `ref` 当作普通 prop 传入，因此这里无需 `forwardRef`；这同时让每个组件都可以直接调用
/// （例如 `List.Dropdown({...props})`），真实扩展常用这种写法让 List 与 Grid 共用同一段代码。
function useFieldRef(ref, { setValue, initial, id }) {
  useImperativeHandle(ref ?? null, () => ({
    focus: () => hostFieldCommand("focus", id),
    reset: () => setValue(initial),
  }));
}

let hostFieldCommand = () => {};
/// 注册宿主侧的字段命令处理器（如 focus）；由运行时入口注入，避免组件直接依赖宿主。
export function setFieldCommandHandler(handler) {
  hostFieldCommand = handler;
}

// ─── List ───────────────────────────────────────────────────────────

/// `throttle` 会等输入停顿后再回调，避免旧查询的慢响应最后才落地、覆盖新结果。
function useThrottledSearch(props) {
  const latest = useRef();
  const timer = useRef();
  latest.current = props.onSearchTextChange;
  useEffect(() => () => clearTimeout(timer.current), []);
  const delayed = useCallback((text) => {
    clearTimeout(timer.current);
    timer.current = setTimeout(() => latest.current?.(text), 300);
  }, []);
  return props.throttle && props.onSearchTextChange ? delayed : props.onSearchTextChange;
}

function List(props) {
  const rest = omit(props, ["children", "actions", "searchBarAccessory"]);
  rest.onSearchTextChange = useThrottledSearch(props);
  // 除非扩展自己接管搜索文本，否则由 Raycast 在客户端做过滤。
  if (rest.filtering === undefined) rest.filtering = props.onSearchTextChange === undefined;
  return h(
    "List",
    rest,
    slot("actions", props.actions),
    slot("searchBarAccessory", props.searchBarAccessory),
    props.children,
  );
}

function ListItem(props) {
  return h(
    "List.Item",
    omit(props, ["children", "actions", "detail"]),
    slot("actions", props.actions),
    slot("detail", props.detail),
    props.children,
  );
}

function ListItemDetail(props) {
  return h("List.Item.Detail", omit(props, ["children", "metadata"]), slot("metadata", props.metadata), props.children);
}

function Section(type) {
  return function SectionComponent(props) {
    return h(type, omit(props, ["children"]), props.children);
  };
}

function EmptyView(type) {
  return function EmptyViewComponent(props) {
    return h(type, omit(props, ["children", "actions"]), slot("actions", props.actions), props.children);
  };
}

/// 构造 List 与 Grid 的搜索栏下拉框。刻意不使用任何 hook：选中状态由 Swift 持有（控件也由它渲染），
/// 初始值来自 `defaultValue`，变更通过 `onChange` 回传。这也让它能安全地被直接调用而非必须走 JSX。
function makeSearchDropdown(type) {
  function Dropdown(props) {
    return h(type, omit(props, ["children"]), props.children);
  }
  Dropdown.Item = Section(`${type}.Item`);
  Dropdown.Section = Section(`${type}.Section`);
  return Dropdown;
}

List.Item = ListItem;
List.Item.Detail = ListItemDetail;
List.Section = Section("List.Section");
List.EmptyView = EmptyView("List.EmptyView");
List.Dropdown = makeSearchDropdown("List.Dropdown");

// ─── Grid ───────────────────────────────────────────────────────────

function Grid(props) {
  const rest = omit(props, ["children", "actions", "searchBarAccessory"]);
  rest.onSearchTextChange = useThrottledSearch(props);
  if (rest.filtering === undefined) rest.filtering = props.onSearchTextChange === undefined;
  return h(
    "Grid",
    rest,
    slot("actions", props.actions),
    slot("searchBarAccessory", props.searchBarAccessory),
    props.children,
  );
}

function GridItem(props) {
  return h("Grid.Item", omit(props, ["children", "actions"]), slot("actions", props.actions), props.children);
}

Grid.Item = GridItem;
Grid.Section = Section("Grid.Section");
Grid.EmptyView = EmptyView("Grid.EmptyView");
Grid.Dropdown = makeSearchDropdown("Grid.Dropdown");

// ─── Detail ─────────────────────────────────────────────────────────

function Detail(props) {
  return h(
    "Detail",
    omit(props, ["children", "actions", "metadata"]),
    slot("actions", props.actions),
    slot("metadata", props.metadata),
    props.children,
  );
}

function DetailMetadata(props) {
  return h("Detail.Metadata", omit(props, ["children"]), props.children);
}
DetailMetadata.Label = Section("Detail.Metadata.Label");
DetailMetadata.Link = Section("Detail.Metadata.Link");
DetailMetadata.Separator = Section("Detail.Metadata.Separator");
DetailMetadata.TagList = Section("Detail.Metadata.TagList");
DetailMetadata.TagList.Item = Section("Detail.Metadata.TagList.Item");

Detail.Metadata = DetailMetadata;
// List.Item.Detail 复用 Detail 的 metadata 组件。
ListItemDetail.Metadata = DetailMetadata;

// ─── Form ───────────────────────────────────────────────────────────

function Form(props) {
  const fields = useRef(new Map()).current;
  const context = useMemo(() => ({ fields, values: () => collectValues(fields) }), [fields]);
  return h(
    FormContext.Provider,
    { value: context },
    h(
      "Form",
      omit(props, ["children", "actions", "searchBarAccessory"]),
      slot("actions", props.actions),
      slot("searchBarAccessory", props.searchBarAccessory),
      props.children,
    ),
  );
}

function collectValues(fields) {
  const values = {};
  for (const [id, field] of fields) values[id] = field.value;
  return values;
}

function makeField(type, fallback) {
  return function Field(props) {
    const [value, setValue] = useFieldValue(props, fallback);
    useFieldRef(props.ref, { setValue, initial: props.defaultValue ?? fallback, id: props.id });
    const rest = omit(props, ["children", "ref", "value", "defaultValue", "onChange", "onBlur", "onFocus"]);
    return h(
      type,
      {
        ...rest,
        value,
        onGearMacChange: (next) => {
          const decoded = type === "Form.DatePicker" ? decodeDate(next) : next;
          setValue(decoded);
          props.onChange?.(decoded);
        },
        onGearMacBlur: props.onBlur ? () => props.onBlur({ target: { value } }) : undefined,
        onGearMacFocus: props.onFocus ? () => props.onFocus({ target: { value } }) : undefined,
      },
      props.children,
    );
  };
}

function decodeDate(value) {
  if (value === null || value === undefined || value === "") return null;
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

Form.TextField = makeField("Form.TextField", "");
Form.PasswordField = makeField("Form.PasswordField", "");
Form.TextArea = makeField("Form.TextArea", "");
Form.Checkbox = makeField("Form.Checkbox", false);
Form.DatePicker = makeField("Form.DatePicker", null);
Form.DatePicker.Type = undefined; // 由 index.js 从生成的 enums 中填充
Form.TagPicker = makeField("Form.TagPicker", []);
Form.TagPicker.Item = Section("Form.TagPicker.Item");
Form.FilePicker = makeField("Form.FilePicker", []);
Form.Separator = Section("Form.Separator");
Form.Description = Section("Form.Description");
Form.LinkAccessory = Section("Form.LinkAccessory");
// 与上面的搜索栏下拉框不同，表单下拉框是一个携带值的字段。
Form.Dropdown = makeField("Form.Dropdown", "");
Form.Dropdown.Item = Section("Form.Dropdown.Item");
Form.Dropdown.Section = Section("Form.Dropdown.Section");
// 已废弃的扁平别名（`Form.DropdownItem` 等）仍出现在已发布的扩展包中。
Form.DropdownItem = Form.Dropdown.Item;
Form.DropdownSection = Form.Dropdown.Section;
Form.TagPickerItem = Form.TagPicker.Item;

// ─── ActionPanel / Action ───────────────────────────────────────────

function ActionPanel(props) {
  return h("ActionPanel", omit(props, ["children"]), props.children);
}
ActionPanel.Section = Section("ActionPanel.Section");
// 保留的废弃别名，因为已安装的扩展仍在打包使用它。
ActionPanel.Item = Action;
ActionPanel.Submenu = function Submenu(props) {
  return h("ActionPanel.Submenu", omit(props, ["children"]), props.children);
};

/// 所有便捷 action 都汇聚到这一个宿主节点，因此 Swift 侧只需要渲染 "Action"。
function Action(props) {
  return h("Action", omit(props, ["children"]));
}

/// 便捷 action 所需的宿主绑定。由 index.js 注入，以避免组件与它驱动的系统 API 之间形成循环导入。
let effects = {};
export function setActionEffects(next) {
  effects = next;
}

function convenience(displayName, build) {
  const Component = function ConvenienceAction(props) {
    return h(Action, build(props));
  };
  Component.displayName = displayName;
  return Component;
}

Action.CopyToClipboard = convenience("Action.CopyToClipboard", (props) => ({
  title: props.title ?? "Copy to Clipboard",
  icon: props.icon ?? Icon.CopyClipboard,
  shortcut: props.shortcut,
  style: props.style,
  autoFocus: props.autoFocus,
  onAction: async () => {
    await effects.copy({ content: props.content, concealed: props.concealed });
    props.onCopy?.(props.content);
  },
}));

Action.Paste = convenience("Action.Paste", (props) => ({
  title: props.title ?? "Paste in Active App",
  icon: props.icon ?? Icon.Clipboard,
  shortcut: props.shortcut,
  style: props.style,
  autoFocus: props.autoFocus,
  onAction: async () => {
    await effects.paste({ content: props.content });
    props.onPaste?.(props.content);
  },
}));

Action.OpenInBrowser = convenience("Action.OpenInBrowser", (props) => ({
  title: props.title ?? "Open in Browser",
  icon: props.icon ?? Icon.Globe,
  shortcut: props.shortcut,
  style: props.style,
  autoFocus: props.autoFocus,
  onAction: async () => {
    await effects.open({ target: props.url, application: props.application });
    props.onOpen?.(props.url);
  },
}));

Action.Open = convenience("Action.Open", (props) => ({
  title: props.title,
  icon: props.icon ?? Icon.Document,
  shortcut: props.shortcut,
  style: props.style,
  autoFocus: props.autoFocus,
  onAction: async () => {
    await effects.open({ target: props.target, application: props.application });
    props.onOpen?.(props.target);
  },
}));

Action.OpenWith = convenience("Action.OpenWith", (props) => ({
  title: props.title ?? "Open With",
  icon: props.icon ?? Icon.AppWindow,
  shortcut: props.shortcut,
  onAction: async () => {
    await effects.openWith({ path: props.path });
    props.onOpen?.(props.path);
  },
}));

Action.ShowInFinder = convenience("Action.ShowInFinder", (props) => ({
  title: props.title ?? "Show in Finder",
  icon: props.icon ?? Icon.Finder,
  shortcut: props.shortcut,
  onAction: async () => {
    await effects.showInFinder({ path: props.path });
    props.onShow?.(props.path);
  },
}));

Action.Trash = convenience("Action.Trash", (props) => ({
  title: props.title ?? "Move to Trash",
  icon: props.icon ?? Icon.Trash,
  style: props.style ?? ActionStyle.Destructive,
  shortcut: props.shortcut,
  onAction: async () => {
    await effects.trash({ paths: props.paths });
    props.onTrash?.(props.paths);
  },
}));

Action.Push = function ActionPush(props) {
  const { push } = useNavigation();
  return h(Action, {
    title: props.title,
    icon: props.icon,
    shortcut: props.shortcut,
    style: props.style,
    autoFocus: props.autoFocus,
    onAction: () => {
      push(props.target);
      props.onPush?.();
    },
  });
};

Action.SubmitForm = function ActionSubmitForm(props) {
  const form = useContext(FormContext);
  return h(Action, {
    title: props.title ?? "Submit Form",
    icon: props.icon,
    shortcut: props.shortcut,
    style: props.style,
    autoFocus: props.autoFocus,
    onAction: () => props.onSubmit?.(form ? form.values() : {}),
  });
};

Action.CreateSnippet = convenience("Action.CreateSnippet", (props) => ({
  title: props.title ?? "Create Snippet",
  icon: props.icon ?? Icon.Snippets,
  shortcut: props.shortcut,
  onAction: () => effects.createSnippet(props.snippet),
}));

Action.CreateQuicklink = convenience("Action.CreateQuicklink", (props) => ({
  title: props.title ?? "Create Quicklink",
  icon: props.icon ?? Icon.Link,
  shortcut: props.shortcut,
  onAction: () => effects.createQuicklink(props.quicklink),
}));

Action.ToggleQuickLook = convenience("Action.ToggleQuickLook", (props) => ({
  title: props.title ?? "Quick Look",
  icon: props.icon ?? Icon.Eye,
  shortcut: props.shortcut,
  onAction: () => effects.quickLook(props.target),
}));

Action.PickDate = function ActionPickDate(props) {
  return h(Action, {
    title: props.title,
    icon: props.icon ?? Icon.Calendar,
    shortcut: props.shortcut,
    style: props.style,
    // 渲染为不带子菜单的 action；Swift 会打开自己的日期选择器，并通过 onChange 回传结果。
    pickDate: { type: props.type, min: props.min, max: props.max },
    onGearMacChange: (value) => props.onChange?.(decodeDate(value)),
  });
};
Action.PickDate.Type = undefined; // 由 index.js 从生成的 enums 中填充

Action.InstallMCPServer = convenience("Action.InstallMCPServer", (props) => ({
  title: props.title ?? "Install MCP Server",
  icon: props.icon ?? Icon.Plug,
  shortcut: props.shortcut,
  onAction: () => effects.unsupported("Action.InstallMCPServer"),
}));

// ─── 菜单栏 ─────────────────────────────────────────────────────────

function MenuBarExtra(props) {
  return h("MenuBarExtra", omit(props, ["children"]), props.children);
}
MenuBarExtra.Item = (props) =>
  h("MenuBarExtra.Item", omit(props, ["children", "alternate"]), slot("alternate", props.alternate));
MenuBarExtra.Submenu = Section("MenuBarExtra.Submenu");
MenuBarExtra.Section = Section("MenuBarExtra.Section");
MenuBarExtra.Separator = Section("MenuBarExtra.Separator");

export { List, Grid, Detail, Form, ActionPanel, Action, MenuBarExtra, FormContext };
