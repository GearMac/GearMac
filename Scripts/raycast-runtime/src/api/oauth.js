// 文件职责：实现 @raycast/api 的 OAuth 子集：PKCE 授权码流程、TokenSet 以及令牌的读写与清除。
// 分层：运行时 shim（JS）；随机数与哈希通过 hostCall 交给 Swift 宿主，本文件只做 PKCE 编码与状态组装。
import { base64ToBytes, bytesToBase64, utf8Encode } from "../polyfills.js";
import { hostCall, hostCallSync } from "../host.js";
import { nestedEnums } from "./enums.generated.js";

/// 向宿主请求密码学随机字节。
function generateRandomBytes(length) {
  const base64 = hostCallSync("crypto", "random", [length]);
  return base64ToBytes(base64);
}

/// 默认参数为 base64url 编码（base64 的 `+`/`/` 替换为 `-`/`_` 并去掉尾部 `=`）。
function base64UrlEncode(bytes) {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function generateCodeVerifier() {
  const bytes = generateRandomBytes(32);
  return base64UrlEncode(bytes);
}

/// 对 verifier 做 SHA-256 并 base64url 编码，得到 PKCE 的 code_challenge。
function computeCodeChallenge(verifier) {
  const verifierBytes = utf8Encode(verifier);
  const hashBase64 = hostCallSync("crypto", "hash", ["sha256", bytesToBase64(verifierBytes), null]);
  const hashBytes = base64ToBytes(hashBase64);
  return base64UrlEncode(hashBytes);
}

/// 生成不含填充的随机字符串（默认 16 字节），用作 state 中的随机 token。
function generateRandomString(length = 16) {
  const bytes = generateRandomBytes(length);
  return base64UrlEncode(bytes);
}

function generateState(client) {
  // raycast.com/redirect 要求 state 是一个 base64url 编码的 JSON 对象，
  // 其中包含 providerName 和 scheme（"gearmac"），这样才会重定向到 gearmac://oauth。
  const payload = {
    token: generateRandomString(16),
    providerName: client?.providerName || "",
    providerId: client?.providerId || "",
    scheme: "gearmac",
  };
  const json = JSON.stringify(payload);
  const bytes = utf8Encode(json);
  return base64UrlEncode(bytes);
}

/// OAuth 令牌集合：兼容驼峰/下划线两种字段名，并带上记录时间以便判断过期。
export class TokenSet {
  constructor(options = {}) {
    this.accessToken = options.accessToken ?? options.access_token ?? "";
    this.refreshToken = options.refreshToken ?? options.refresh_token;
    this.idToken = options.idToken ?? options.id_token;
    this.tokenType = options.tokenType ?? options.token_type ?? "Bearer";
    this.scope = options.scope;
    this.expiresIn = options.expiresIn ?? options.expires_in;
    this.updatedAt = new Date(options.updatedAt ?? Date.now());
  }

  /// 已过期或即将过期（提前 30 秒）时返回 true；无 expiresIn 时视为永不过期。
  isExpired() {
    if (this.expiresIn == null) return false;
    const expiresAt = this.updatedAt.getTime() + (this.expiresIn - 30) * 1000;
    return Date.now() >= expiresAt;
  }
}

/// 基于 PKCE 的 OAuth 客户端：拼授权 URL、发起 authorize 并向宿主读写令牌。
export class PKCEClient {
  constructor(options = {}) {
    this.redirectMethod = options.redirectMethod || nestedEnums.OAuth.RedirectMethod.Web;
    this.providerName = options.providerName || "";
    this.providerIcon = options.providerIcon;
    this.providerId = options.providerId || "";
    this.description = options.description || "";
  }

  /// 根据 endpoint/clientId 构建 PKCE 授权请求（含 code_challenge 与 state）。
  async authorizationRequest(options) {
    if (!options || !options.endpoint || !options.clientId) {
      throw new Error("authorizationRequest requires endpoint and clientId");
    }

    const codeVerifier = generateCodeVerifier();
    const codeChallenge = computeCodeChallenge(codeVerifier);
    const codeChallengeMethod = "S256";
    const state = options.state || generateState(this);

    let redirectURI = options.extraParameters?.redirect_uri;
    if (!redirectURI) {
      if (this.redirectMethod === nestedEnums.OAuth.RedirectMethod.App) {
        redirectURI = "raycast://oauth?package_name=Extension";
      } else if (this.redirectMethod === nestedEnums.OAuth.RedirectMethod.AppURI) {
        redirectURI = "com.raycast:/oauth?package_name=Extension";
      } else {
        redirectURI = "https://raycast.com/redirect?packageName=Extension";
      }
    }

    const url = new URL(options.endpoint);
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", options.clientId);
    if (options.scope) {
      url.searchParams.set("scope", options.scope);
    }
    url.searchParams.set("redirect_uri", redirectURI);
    url.searchParams.set("code_challenge", codeChallenge);
    url.searchParams.set("code_challenge_method", codeChallengeMethod);
    url.searchParams.set("state", state);

    if (options.extraParameters) {
      for (const [key, value] of Object.entries(options.extraParameters)) {
        if (value !== undefined && value !== null) {
          url.searchParams.set(key, String(value));
        }
      }
    }

    return {
      endpoint: options.endpoint,
      clientId: options.clientId,
      scope: options.scope,
      codeVerifier,
      codeChallenge,
      codeChallengeMethod,
      state,
      redirectURI,
      toURL() {
        return url.toString();
      },
    };
  }

  /// 向宿主发起授权流程，并归一化返回的授权码/令牌。
  async authorize(request) {
    const url =
      typeof request === "string"
        ? request
        : request?.toURL
        ? request.toURL()
        : request?.url || request?.endpoint;
    if (!url) {
      throw new Error("authorize requires a valid authorization URL");
    }
    const state = typeof request === "object" ? request?.state : undefined;

    let res = await hostCall("oauth", "authorize", [url, state]);

    if (typeof res === "string") {
      try {
        res = JSON.parse(res);
      } catch {}
    }

    return {
      authorizationCode: res?.authorizationCode ?? res?.code ?? "",
      accessToken: res?.accessToken,
      state: res?.state,
    };
  }

  /// 读取本 provider 已保存的令牌；不存在时返回 undefined。
  async getTokens() {
    let raw = await hostCall("oauth", "getTokens", [this.providerId]);
    if (!raw) return undefined;
    if (typeof raw === "string") {
      try {
        raw = JSON.parse(raw);
      } catch {
        return undefined;
      }
    }
    // 未记录时间戳的令牌无法判断签发时间，因此一律视为已过期并走刷新流程。
    return new TokenSet({ ...raw, updatedAt: raw.updatedAt ?? 0 });
  }

  /// 保存令牌，并写入当前时间供后续判断过期。
  async setTokens(tokens) {
    const set = typeof tokens === "string" ? JSON.parse(tokens) : tokens;
    const stamped = JSON.stringify({ ...set, updatedAt: new Date().toISOString() });
    await hostCall("oauth", "setTokens", [this.providerId, stamped]);
  }

  /// 删除本 provider 已保存的令牌。
  async removeTokens() {
    await hostCall("oauth", "removeTokens", [this.providerId]);
  }
}
