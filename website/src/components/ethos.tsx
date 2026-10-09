// 文件职责：页面收尾的理念区块，渲染一段引言与四个理念支柱（原生、本地、开源、免费）。
// 分层：网站 UI 组件；衬线字体仅在此处出现，使这段读起来像一句声明。
import { Cpu, Heart, Lock, ShieldCheck } from "lucide-react";
import type { ComponentType } from "react";
import { ethos, ethosPillars, type EthosPillar } from "../data/ethos";

// 每根理念支柱对应的图标。
const pillarIcons: Record<
  EthosPillar["icon"],
  ComponentType<{ size?: number; className?: string }>
> = {
  native: Cpu,
  local: Lock,
  source: ShieldCheck,
  free: Heart,
};

// 页面收尾声明，做成一条延伸到窗口边缘的色带。它也是衬线字体
// 唯一出现的地方，这正是它读起来像声明而不是又一个区块的原因。
export function Ethos() {
  return (
    <section id="ethos" className="border-y border-border bg-tint/2">
      <div className="mx-auto max-w-7xl px-4 py-20 sm:px-10">
        <blockquote className="mx-auto max-w-3xl text-center">
          <p className="text-quote text-balance font-serif text-fg">
            &ldquo;{ethos.quote}{" "}
            <em className="italic text-violet">{ethos.emphasis}</em>&rdquo;
          </p>
          <footer className="mt-4 text-small text-fg-subtle">
            {ethos.attribution}
          </footer>
        </blockquote>

        <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {ethosPillars.map((pillar) => {
            const Icon = pillarIcons[pillar.icon];
            return (
              <div key={pillar.title}>
                <Icon size={18} className="text-fg-subtle" />
                <h3 className="mt-3 text-body font-semibold text-fg">
                  {pillar.title}
                </h3>
                <p className="mt-1.5 text-small text-fg-muted">{pillar.body}</p>
              </div>
            );
          })}
        </div>
      </div>
    </section>
  );
}
