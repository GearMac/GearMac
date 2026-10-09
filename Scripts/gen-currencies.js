#!/usr/bin/env node
// 文件职责：生成 GearMac/Features/Calculator/Model/CurrencyData.generated.swift，即法币的展示名、符号与量词别名表。
// 分层：脚本（代码生成器）；产物是 generated 文件，只能由本脚本生成，禁止手改。
//
// 用法：node Scripts/gen-currencies.js [rates.json cldr-currencies.json cldr-currency-data.json]
// 未给出路径时从网络下载数据源。偶尔跑一次，并把输出一并提交。
//
// 三个数据源，按 ISO 代码关联：
//   - 法币汇率源决定*存在哪些*货币 —— 与 CurrencyRateStore 取汇率的正是同一个源，因此这张表永远不会
//     列出应用无法定价的货币。
//   - CLDR 的 supplemental 货币数据决定其中哪些仍在*流通*。汇率源不带停用日期，会照旧报价那些国家
//     多年前就废弃的代码。
//   - CLDR 的 `en` numbers 数据决定人们对它们的*称呼*：展示名、货币符号与单复数名词。数据取自固定版本的
//     cldr-json 检出，而不是宿主机的 `Intl`，后者的输出会随本地 ICU 版本漂移，使本文件不可复现。
//
// 只输出无歧义的数据。被多个货币共用的符号或名词一律剔除，改由 CalcCurrency.swift 手工决定 —— 因为选哪个
// 是产品决策，而不是一次查表。加密货币同样手写在 CalcCurrency.swift 里 —— 没有任何标准机构为它命名。
"use strict";

const fs = require("fs");
const path = require("path");

const RATES = "https://backend.raycast.com/api/v1/currencies";
const CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json";
const CLDR_NAMES = `${CLDR}/cldr-numbers-full/main/en/currencies.json`;
const CLDR_CURRENCY_DATA = `${CLDR}/cldr-core/supplemental/currencyData.json`;

// 汇率源提供约 170 个代码，约 159 个能通过过滤；明显低于这个数量说明响应异常。
const MIN_EXPECTED = 150;
// 这一项归 CalcCurrency.swift 里的加密货币表管，并由专用行情源定价。
const CRYPTO_OWNED = new Set(["BTC"]);
// CLDR 没有给王室属地的英镑提供名称，而汇率源根本不提供任何名称。
const UNNAMED = { GGP: "Guernsey Pound", IMP: "Isle of Man Pound", JEP: "Jersey Pound" };

/// 读取本地 JSON 文件，或从 url 下载并解析。
async function load(url, argPath) {
  if (argPath) return JSON.parse(fs.readFileSync(argPath, "utf8"));
  const response = await fetch(url);
  if (!response.ok) throw new Error(`${url} -> HTTP ${response.status}`);
  return response.json();
}

/// 折叠一个字符串：NFD 分解后删除组合记号（变音符）。
const fold = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "");
// 符号必须是分词器一眼就能认出的标点。CLDR 也会列出裸的拉丁字母（BWP 的 "P"、HNL 的 "L"）；
// 它们与普通单词无法区分，因此绝不能出现。
const isSign = (s) => [...s].length === 1 && !/[\p{L}\p{N}]/u.test(s);

// 把每个单词首字母大写、其余不动，于是 "UAE dirham" 会保持为 "UAE Dirham"。
const titleCase = (s) => s.replace(/(^|[\s(])(\p{Ll})/gu, (_, lead, c) => lead + c.toUpperCase());

// 名词取名字的最后一个词，只有在该词本身不是钱的量词时才会出错：没人会说兑换 "1 rights"。
// 直接列出这些例外，比去解析语法更可靠。
const NOT_NOUNS = new Set(["rights"]);

/// 卡片上的徽标是一个小 pill，所以取 CLDR 两种写法中较短的那个：`displayName` 是
/// 首字母大写的标签（"US Dollar"），但对少数货币来说单数形式紧凑得多
/// （"United Arab Emirates Dirham" 对 "UAE dirham"）。
function displayName(entry, fallback) {
  const long = entry?.displayName || fallback;
  const short = titleCase(entry?.["displayName-count-one"] || "");
  return short && short.length < long.length ? short : long;
}

/// 只保留恰好只有一个货币主张的条目。
function unambiguous(claims) {
  return new Map(
    [...claims].filter(([, owners]) => owners.size === 1).map(([key, owners]) => [key, [...owners][0]]),
  );
}

function claim(map, key, code) {
  if (!map.has(key)) map.set(key, new Set());
  map.get(key).add(code);
}

function swiftString(value) {
  if (value.includes('"') || value.includes("\\")) throw new Error(`unsafe literal ${JSON.stringify(value)}`);
  return `"${value}"`;
}

/// 返回一个判定函数，用于回答「某代码是否仍在使用」：CLDR 完全没听说过的代码保留，
/// CLDR 知道但已无地区在用的代码剔除。没有证据不等于停用，这也正是 CNH、XAU、XDR 以及
/// 王室属地各磅能被保留的原因 —— 它们都不是任何地区的法定货币。
function inUse(currencyData) {
  const known = new Set();
  const live = new Set();
  for (const entries of Object.values(currencyData.region)) {
    for (const entry of entries) {
      for (const [code, meta] of Object.entries(entry)) {
        known.add(code);
        if (!("_to" in meta)) live.add(code);
      }
    }
  }
  return (code) => live.has(code) || !known.has(code);
}

/// 拉取三个数据源，生成展示名、符号与量词别名表并写入 generated 文件。
async function main() {
  const feed = await load(RATES, process.argv[2]);
  const cldr = await load(CLDR_NAMES, process.argv[3]);
  const supplemental = await load(CLDR_CURRENCY_DATA, process.argv[4]);
  const base = feed?.source;
  const quotes = feed?.quotes;
  // 出错时响应体也会带 HTTP 200，所以只有这个标志位能说明表是真的。
  if (feed?.success !== true) throw new Error("the rate feed reported failure");
  if (!base || !quotes || typeof quotes !== "object")
    throw new Error("unexpected feed shape: source/quotes missing");
  const names = cldr?.main?.en?.numbers?.currencies;
  if (!names) throw new Error("unexpected CLDR shape: main.en.numbers.currencies missing");
  if (!supplemental?.supplemental?.currencyData?.region)
    throw new Error("unexpected CLDR shape: supplemental.currencyData.region missing");

  // 汇率以 "<base><code>" 为键，且不含基准自身那一行，所以要把它补回来。
  const quoted = new Set([base]);
  for (const pair of Object.keys(quotes)) {
    if (pair.length === 6 && pair.startsWith(base)) quoted.add(pair.slice(3));
  }

  const stillInUse = inUse(supplemental.supplemental.currencyData);
  const codes = [...quoted]
    .filter((code) => /^[A-Z]{3}$/.test(code) && !CRYPTO_OWNED.has(code) && stillInUse(code))
    .sort();
  const retired = quoted.size - CRYPTO_OWNED.size - codes.length;
  const asOf = new Date((feed.timestamp || Date.now() / 1000) * 1000).toISOString().slice(0, 10);
  if (codes.length < MIN_EXPECTED) throw new Error(`suspiciously few currencies: ${codes.length}`);

  const signClaims = new Map();
  const narrowClaims = new Map();
  const wordClaims = new Map();
  const rows = [];
  let uncovered = 0;

  for (const code of codes) {
    const cldrEntry = names[code];
    if (!cldrEntry) uncovered += 1;

    rows.push([code, displayName(cldrEntry, UNNAMED[code] || code)]);
    if (!cldrEntry) continue;

    if (cldrEntry.symbol && isSign(cldrEntry.symbol)) claim(signClaims, cldrEntry.symbol, code);
    if (cldrEntry["symbol-alt-narrow"] && isSign(cldrEntry["symbol-alt-narrow"]))
      claim(narrowClaims, cldrEntry["symbol-alt-narrow"], code);

    // 名词取名字的最后一个词（"US dollars" -> "dollars"）。带变音符的形式同时按原样与折叠后登记，
    // 于是 "krónur" 和 "kronur" 在非美式键盘上都能命中。
    for (const field of ["displayName-count-one", "displayName-count-other"]) {
      const word = (cldrEntry[field] || "").toLowerCase().split(/\s+/).filter(Boolean).pop() || "";
      if (word.length < 3 || !/^\p{L}+$/u.test(word) || NOT_NOUNS.has(word)) continue;
      for (const form of new Set([word, fold(word), fold(word).replace(/[^a-z]/g, "")]))
        if (form.length >= 3) claim(wordClaims, form, code);
    }
  }

  // 标准符号优先：除 USD 外，CLDR 把每个 dollar 都写成 "CA$"/"A$"/"NT$"，这正好就是判别依据。
  // 窄符号只用来补空缺，且在那里同样是唯一的（RUB 的 ₽、THB 的 ฿）。
  const signs = unambiguous(signClaims);
  for (const [sign, code] of unambiguous(narrowClaims)) if (!signs.has(sign)) signs.set(sign, code);
  const aliases = unambiguous(wordClaims);

  const out = path.resolve(__dirname, "..", "GearMac/Features/Calculator/Model/CurrencyData.generated.swift");
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(
    out,
    "// Generated by Scripts/gen-currencies.js — do not edit by hand.\n" +
      `// Codes from the fiat rate feed (as of ${asOf}), minus those Unicode CLDR records as retired;\n` +
      "// names, signs and nouns from CLDR (en). Ambiguous signs and nouns are deliberately absent,\n" +
      "// and so is crypto — CalcCurrency.swift decides both.\n" +
      "enum CurrencyData {\n" +
      "    /// Every fiat currency the rate feed prices, as (ISO 4217 code, display name).\n" +
      "    static let all: [(code: String, name: String)] = [\n" +
      rows.map(([c, n]) => `        (${swiftString(c)}, ${swiftString(n)}),`).join("\n") +
      "\n    ]\n\n" +
      "    /// Currency sign → ISO code, lowercased to match the tokenizer's ident form. Only signs CLDR\n" +
      "    /// assigns to exactly one currency, so `$` is USD and `¥` is JPY without any guessing here.\n" +
      "    static let signs: [Character: String] = [\n" +
      [...signs]
        .sort((a, b) => a[1].localeCompare(b[1]))
        .map(([s, c]) => `        ${swiftString(s)}: ${swiftString(c.toLowerCase())},`)
        .join("\n") +
      "\n    ]\n\n" +
      "    /// Currency noun → ISO code, for nouns exactly one currency uses. Contested ones\n" +
      "    /// (`dollars`, `pounds`, `francs`…) are absent by design; CalcCurrency assigns those.\n" +
      "    static let aliases: [String: String] = [\n" +
      [...aliases]
        .sort((a, b) => a[0].localeCompare(b[0]))
        .map(([w, c]) => `        ${swiftString(w)}: ${swiftString(c)},`)
        .join("\n") +
      "\n    ]\n" +
      "}\n",
  );
  console.log(
    `wrote ${out} — ${rows.length} currencies ` +
      `(${retired} retired, ${uncovered} without CLDR names), ` +
      `${signs.size} signs, ${aliases.size} aliases`,
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
