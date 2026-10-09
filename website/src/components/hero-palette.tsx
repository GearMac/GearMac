// 文件职责：复刻应用命令面板外观的 Hero 示意图，绘制搜索框、分组结果与底部操作栏。
// 分层：网站 UI 组件；纯装饰（aria-hidden），内部不使用分隔线。
import {
  AudioLines,
  Gem,
  Ghost,
  Hammer,
  Orbit,
  Search,
  Shield,
} from "lucide-react";
import type { ComponentType } from "react";
import {
  demoAction,
  demoQuery,
  demoSections,
  type DemoRow,
  type DemoRowIcon,
} from "../data/demo";
import { cn } from "../lib/cn";

// 演示行图标名到 lucide 图标的映射。
const rowIcons: Record<DemoRowIcon, ComponentType<{ size?: number }>> = {
  ghost: Ghost,
  hammer: Hammer,
  shield: Shield,
  gem: Gem,
  orbit: Orbit,
  audio: AudioLines,
};

// 命令面板左上角的菜单图标。
function MenuGlyph() {
  return (
    <span className="flex flex-col items-start gap-[3px]">
      <span className="h-[1.5px] w-3.5 rounded-full bg-current" />
      <span className="h-[1.5px] w-2 rounded-full bg-current" />
    </span>
  );
}

// 单个按键帽。
function Keycap({ children }: { children: string }) {
  return (
    <span className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-[6px] border border-(--glass-border) px-1 text-demo-key text-(--glass-fg-muted)">
      {children}
    </span>
  );
}

// 图标填满 26px 槽位中的 22px，这是 macOS 应用图标在画布内留出的边距。
function RowIcon({ row }: { row: DemoRow }) {
  const Icon = rowIcons[row.icon];
  return (
    <span className="flex size-[26px] shrink-0 items-center justify-center">
      <span
        className="glass-app-icon flex size-[22px] items-center justify-center rounded-[5px] text-white"
        style={{ background: row.tint }}
      >
        <Icon size={13} />
      </span>
    </span>
  );
}

// 单条搜索结果行：图标、标题、可选快捷键与右侧类型标签。
function ResultRow({ row, isSelected }: { row: DemoRow; isSelected: boolean }) {
  return (
    <li
      className={cn(
        "flex items-center gap-2.5 rounded-[10px] px-2 py-1.5",
        isSelected && "bg-(--glass-selection)",
      )}
    >
      <RowIcon row={row} />
      <span className="min-w-0 truncate text-demo-row text-(--glass-fg)">
        {row.title}
      </span>
      {row.hotkey && (
        <span className="flex shrink-0 gap-0.5">
          {row.hotkey.map((key) => (
            <Keycap key={key}>{key}</Keycap>
          ))}
        </span>
      )}
      <span className="ml-auto shrink-0 text-demo-callout text-(--glass-fg-muted)">
        {row.kind}
      </span>
    </li>
  );
}

// 按应用真实绘制方式还原的命令面板。内部不使用任何分隔线：
// 真实窗口仅用间距区分搜索框、列表与操作栏，
// 而一条细线正是让拟真图看起来像网页卡片的东西。
export function HeroPalette() {
  return (
    <div
      aria-hidden="true"
      className="glass-palette w-full rounded-[26px] text-left"
    >
      <span aria-hidden="true" className="glass-grain" />

      {/* 图标的左边缘与下方各行的图标对齐。 */}
      <div className="mt-1.5 flex h-10 items-center gap-2 px-4">
        <Search
          size={22}
          strokeWidth={1.75}
          className="shrink-0 text-(--glass-fg-muted)"
        />
        <span className="flex min-w-0 flex-1 items-center text-demo-query text-(--glass-fg)">
          <span className="truncate">{demoQuery}</span>
          <span className="demo-caret ml-px h-[1.1em] w-0.5 shrink-0 rounded-full bg-violet-bright" />
        </span>
      </div>

      {/* 最后一行落在页脚线上，在悬浮控件下渐渐淡出，
          正如应用中列表溢出时的样子。 */}
      <div className="glass-dissolve px-2 pb-2">
        {demoSections.map((section, sectionIndex) => (
          <div key={section.title}>
            <p
              className={cn(
                "px-2 pb-1 text-demo-section font-medium text-(--glass-fg-muted)",
                sectionIndex === 0 ? "pt-1" : "pt-3",
              )}
            >
              {section.title}
            </p>
            <ul>
              {section.rows.map((row, rowIndex) => (
                <ResultRow
                  key={row.title}
                  row={row}
                  isSelected={sectionIndex === 0 && rowIndex === 0}
                />
              ))}
            </ul>
          </div>
        ))}
      </div>

      <div className="absolute inset-x-0 bottom-0 flex h-[52px] items-center justify-between px-2">
        <span className="glass-control flex size-9 items-center justify-center rounded-full text-(--glass-fg-muted)">
          <MenuGlyph />
        </span>
        <span className="glass-control flex items-center gap-0.5 rounded-full p-1 text-demo-callout font-medium">
          <span className="flex h-7 items-center gap-1.5 px-2 text-(--glass-fg)">
            {demoAction}
            <Keycap>↵</Keycap>
          </span>
          <span className="flex h-7 items-center gap-1.5 px-2 text-(--glass-fg-muted)">
            Actions
            <span className="flex gap-0.5">
              <Keycap>⌘</Keycap>
              <Keycap>K</Keycap>
            </span>
          </span>
        </span>
      </div>
    </div>
  );
}
