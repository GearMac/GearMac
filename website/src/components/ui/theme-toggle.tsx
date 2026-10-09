"use client";

// 文件职责：外观切换控件，提供三档 ThemeToggle（浅色/跟随系统/深色）与页脚一键 ThemeSwitch。
// 分层：UI（"use client" 客户端组件）；依赖 next-themes，并在 hydration 完成前不展示真实状态。

import { Monitor, Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { useSyncExternalStore } from "react";
import { cn } from "../../lib/cn";

// 空的订阅函数：该 store 的值只取决于是否已 hydration，不依赖任何订阅。
const noop = () => () => {};

// 服务端无法得知已存储的选择，因此任何依赖它的渲染都必须等 hydration 完成，
// 否则会先渲染错误的状态再翻转。
function useHasMounted() {
  return useSyncExternalStore(
    noop,
    () => true,
    () => false,
  );
}

// 三个明确的目标，绝不做成循环按钮：夜里切到浅色会刺眼。
const options = [
  { value: "light", label: "Light", Icon: Sun },
  { value: "system", label: "System", Icon: Monitor },
  { value: "dark", label: "Dark", Icon: Moon },
] as const;

// 三档外观选择器：浅色、跟随系统、深色。
export function ThemeToggle({ className }: { className?: string }) {
  const { theme, setTheme } = useTheme();
  const mounted = useHasMounted();

  return (
    <div
      className={cn(
        "inline-flex items-center gap-1 rounded-full border border-border p-1",
        className,
      )}
      role="radiogroup"
      aria-label="Appearance"
    >
      {options.map(({ value, label, Icon }) => {
        const active = mounted && theme === value;
        return (
          <button
            key={value}
            type="button"
            role="radio"
            aria-checked={active}
            aria-label={label}
            title={label}
            onClick={() => setTheme(value)}
            className={cn(
              "flex size-8 items-center justify-center rounded-full transition-colors",
              active
                ? "bg-tint/10 text-fg"
                : "text-fg-subtle hover:bg-tint/5 hover:text-fg",
            )}
          >
            <Icon size={16} strokeWidth={1.9} />
          </button>
        );
      })}
    </div>
  );
}

// 页头的一键浅色/深色切换。它不是上面三档控件的替代：三档仍然负责 System，
// 而一键切换无法切到 System，所以页脚保留了三档控件。
export function ThemeSwitch({ className }: { className?: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  const mounted = useHasMounted();
  const isDark = mounted && resolvedTheme === "dark";
  const Icon = isDark ? Sun : Moon;

  return (
    <button
      type="button"
      onClick={() => setTheme(isDark ? "light" : "dark")}
      aria-label={isDark ? "Switch to light" : "Switch to dark"}
      title={isDark ? "Switch to light" : "Switch to dark"}
      className={cn(
        "flex size-8 items-center justify-center rounded-full text-fg-muted transition-colors hover:bg-tint/5 hover:text-fg",
        className,
      )}
    >
      {mounted ? (
        <Icon size={16} strokeWidth={1.9} />
      ) : (
        <span className="size-4" />
      )}
    </button>
  );
}
