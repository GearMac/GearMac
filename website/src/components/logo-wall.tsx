// 文件职责：Logo 墙，将企业 Logo 列表复制一份做无缝横向滚动。
// 分层：网站 UI 组件；轨道渲染两份并位移 50% 以保证循环无缝。
import { companies } from "../data/site";
import { CompanyLogo } from "./ui/company-logos";

// 列表渲染两份，轨道恰好滚动自身体宽的一半，
// 于是第二份恰好落到第一份的起点，循环便没有接缝。
const track = [...companies, ...companies];

// Logo 墙：展示给 GearMac 点过 star 的公司。
export function LogoWall() {
  return (
    <section
      aria-label="Companies whose people have starred GearMac"
      className="border-y border-border bg-tint/2"
    >
      <div className="mx-auto max-w-7xl px-4 py-6 sm:px-10">
        <p className="text-center font-mono text-eyebrow uppercase text-fg-subtle">
          Starred on GitHub by people at
        </p>
        <div
          className="mt-4 overflow-hidden"
          style={{
            maskImage:
              "linear-gradient(to right, transparent, #000 6%, #000 94%, transparent)",
          }}
        >
          {/* 间距是每个条目的 padding，绝不用 flex 的 `gap`。
              gap 只存在于条目之间、最后一项之后没有，
              于是它的一半会落在 -50% 平移的中点，循环便在此处跳断。 */}
          <ul className="flex w-max animate-marquee items-center">
            {track.map((company, index) => (
              <li
                key={`${company}-${index}`}
                aria-hidden={index >= companies.length}
                className="pr-16"
              >
                <CompanyLogo
                  id={company}
                  className="opacity-70 transition-opacity hover:opacity-100"
                />
              </li>
            ))}
          </ul>
        </div>
      </div>
    </section>
  );
}
