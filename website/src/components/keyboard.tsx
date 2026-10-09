// 文件职责：键盘快捷键区块，渲染常用快捷键列表与指向完整快捷键文档的链接。
// 分层：网站 UI 组件；按键帽使用无衬线字体栈，以正确显示 ⌘ ⌥ ⇧。
import { shortcutRows } from "../data/shortcuts";
import { Link } from "./ui/link";
import { Section } from "./ui/section";

// 键盘区块：常用快捷键列表 + 完整快捷键文档链接。
export function Keyboard() {
  return (
    <Section
      id="keyboard"
      index={4}
      label="Keyboard"
      title="Built for the keyboard."
      intro="Choose one shortcut to open the palette. Everything else has a key, and shortcuts follow key position, so they work with any keyboard layout."
    >
      <dl className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {shortcutRows.map((row) => (
          <div
            key={row.does}
            className="flex flex-col gap-3 rounded-xl bg-tint/4 p-4"
          >
            <dt>
              {/* 用无衬线字体栈而非等宽：没有任何等宽字体能绘制 ⌘ ⌥ ⇧。 */}
              <kbd className="inline-flex h-7 min-w-9 items-center justify-center gap-1 whitespace-nowrap rounded-md border border-border bg-surface px-2 font-sans text-small font-medium text-fg shadow-cap">
                {row.keys.join(" ")}
              </kbd>
            </dt>
            <dd className="text-small text-fg-muted">{row.does}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-4 text-small text-fg-muted">
        Every other key, one table per screen, is in{" "}
        <Link
          href="/docs/reference/shortcuts"
          className="text-fg underline decoration-border-strong underline-offset-4 transition-colors hover:decoration-violet-bright"
        >
          Keyboard shortcuts
        </Link>
        .
      </p>
    </Section>
  );
}
