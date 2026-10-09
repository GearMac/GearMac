// 文件职责：Cloudflare Worker 入口，提供 /api/supporters 与 /api/checkout 两个接口，其余请求交给静态资源。
// 分层：Service（边缘运行时）；Polar token 缺失时接口降级而不报错，本地开发仍能正常提供站点。

import { PolarCore } from "@polar-sh/sdk/core.js";
import { checkoutsCreate } from "@polar-sh/sdk/funcs/checkoutsCreate.js";
import { countSupporters } from "./supporters";

// 贡献者本地运行时不存在，但本地仍必须能正常提供站点。
type WorkerEnv = Env & { POLAR_ACCESS_TOKEN?: string };

// 与前端一致的方案枚举。
type Plan = "monthly" | "one-time";

// 计数落后几分钟可以接受，这样能让大多数页面加载不触碰 Polar。
const SUPPORTERS_CACHE_SECONDS = 600;
const MAX_AMOUNT = 10_000;

// 统一的 JSON 响应构造：按需设置缓存头，并对所有接口响应加 noindex。
function json(body: unknown, status = 200, cacheSeconds = 0): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": cacheSeconds
        ? `public, max-age=${cacheSeconds}`
        : "no-store",
      "X-Robots-Tag": "noindex",
    },
  });
}

// 构造 Polar SDK 客户端。
function polar(env: WorkerEnv, accessToken: string): PolarCore {
  // .dev.vars 里可能写 "sandbox"；生成的类型只知道线上部署的值。
  const server = env.POLAR_SERVER as "production" | "sandbox";
  return new PolarCore({ accessToken, server });
}

// GET /api/supporters：返回付费支持者总数，并利用 Worker 边缘缓存。
async function supporters(
  request: Request,
  env: WorkerEnv,
  ctx: ExecutionContext,
): Promise<Response> {
  const token = env.POLAR_ACCESS_TOKEN;
  if (!token) return json({ total: 0 });

  // 无论查询串是什么都用同一个缓存键，这样 ?anything 无法绕过缓存去猛打 Polar。
  const key = new Request(new URL("/api/supporters", request.url));
  const cache = caches.default;
  const cached = await cache.match(key);
  if (cached) return cached;
  try {
    const total = await countSupporters(polar(env, token), [
      env.POLAR_PRODUCT_MONTHLY,
      env.POLAR_PRODUCT_ONE_TIME,
    ]);
    const response = json({ total }, 200, SUPPORTERS_CACHE_SECONDS);
    ctx.waitUntil(cache.put(key, response.clone()));
    return response;
  } catch (error) {
    console.error("supporter count failed", error);
    return json({ error: "The supporter count is unavailable." }, 502);
  }
}

// 校验并归一化结账请求体；不合法时返回 null。
function parseCheckout(body: unknown): { plan: Plan; amount: number } | null {
  if (!body || typeof body !== "object") return null;
  const { plan, amount } = body as Record<string, unknown>;
  if (plan !== "monthly" && plan !== "one-time") return null;
  if (!Number.isInteger(amount)) return null;
  const dollars = amount as number;
  if (dollars < 1 || dollars > MAX_AMOUNT) return null;
  return { plan, amount: dollars };
}

// POST /api/checkout：校验请求体、按访客限流，再创建 Polar 结账会话并返回跳转地址。
async function checkout(request: Request, env: WorkerEnv): Promise<Response> {
  const token = env.POLAR_ACCESS_TOKEN;
  if (!token) return json({ error: "Checkout is not configured." }, 503);

  const visitor = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const { success } = await env.CHECKOUT_LIMIT.limit({ key: visitor });
  if (!success) {
    return json({ error: "Too many attempts. Try again in a minute." }, 429);
  }

  const input = parseCheckout(await request.json().catch(() => null));
  if (!input) return json({ error: "Choose a whole amount in dollars." }, 400);

  // 页面也由该 Worker 托管，因此回跳地址就用它自身的 origin。
  const origin = new URL(request.url).origin;
  const result = await checkoutsCreate(polar(env, token), {
    products: [
      input.plan === "monthly"
        ? env.POLAR_PRODUCT_MONTHLY
        : env.POLAR_PRODUCT_ONE_TIME,
    ],
    amount: input.amount * 100,
    successUrl: `${origin}/support/?thanks=${input.plan}`,
    returnUrl: `${origin}/support/`,
    metadata: { source: "support-page", plan: input.plan },
  });
  if (!result.ok) {
    console.error("checkout create failed", result.error);
    return json({ error: "Polar could not start the checkout." }, 502);
  }
  return json({ url: result.value.url });
}

// Worker 入口：处理两个 API 路由，其余请求会正常转发给静态资源。
export default {
  async fetch(request, env, ctx) {
    const { pathname } = new URL(request.url);
    const method = request.method;

    if (pathname === "/api/supporters" && method === "GET") {
      return supporters(request, env, ctx);
    }
    if (pathname === "/api/checkout" && method === "POST") {
      return checkout(request, env);
    }
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<WorkerEnv>;
