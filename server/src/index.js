// 合格ロックの預け金サーバー(Cloudflare Workers)。
// アプリ ⇄ このサーバー ⇄ Stripe。カード番号はアプリの Stripe の画面から Stripe に直接渡り、ここには来ない。
//
//   GET  /v1/config                     預け金の設定(公開鍵・額の範囲など)
//   POST /v1/register                   端末を登録して合い言葉(トークン)を受け取る
//   GET  /v1/state                      預け金の様子(最近の週)
//   POST /v1/deposits                   7日分を預ける支払いを作る(アプリが Stripe の画面で払う)
//   POST /v1/deposits/:id/days/:day     その日の結果を知らせる(達成なら、その日の分を返金)
//   POST /v1/deposits/:id/renew         次の週も自動で預けるか
//   (Cron)                              週が終わった預け金を、保存したカードで次の週へ

import { stripeClient, StripeError } from "./stripe.js";
import { readToken } from "./auth.js";
import { readConfig, publicConfig, depositService, HttpError } from "./deposits.js";

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

async function readBody(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function bearer(request) {
  const header = request.headers.get("Authorization") || "";
  return header.startsWith("Bearer ") ? header.slice(7).trim() : null;
}

function errorResponse(error) {
  if (error instanceof HttpError) {
    return json({ error: { code: error.code, message: error.message } }, error.status);
  }
  if (error instanceof StripeError) {
    // 402:カードが通らないなど(そのまま伝える)。ほかは Stripe とのやりとりの失敗
    return json({ error: { code: error.code || "stripe_error", message: error.message } }, error.status === 402 ? 402 : 502);
  }
  console.error(error);
  return json({ error: { code: "server_error", message: "サーバーでうまくいきませんでした" } }, 500);
}

/**
 * @param {Request} request
 * @param {Record<string, string>} env
 * @param {{ now?: () => number, fetch?: typeof fetch, stripe?: object }} deps テスト用
 */
export async function handle(request, env, deps = {}) {
  const cfg = readConfig(env);
  const now = deps.now ?? (() => Math.floor(Date.now() / 1000));
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  const method = request.method;
  try {
    if (method === "GET" && (path === "/" || path === "/v1")) return json({ ok: true, service: "goukaku-deposit" });
    if (method === "GET" && path === "/v1/config") return json(publicConfig(cfg));
    if (!publicConfig(cfg).ready) {
      throw new HttpError(503, "not_configured", "預け金のサーバーの設定がまだです(STRIPE_SECRET_KEY・STRIPE_PUBLISHABLE_KEY・TOKEN_SECRET)");
    }
    const stripe = deps.stripe ?? stripeClient(cfg.secretKey, deps.fetch);
    const service = depositService({ stripe, cfg, now });
    if (method === "POST" && path === "/v1/register") return json(await service.register(await readBody(request)), 201);

    const customerId = await readToken(cfg.tokenSecret, bearer(request));
    if (!customerId) throw new HttpError(401, "unauthorized", "サーバーにつなぎ直してください(合い言葉が合いません)");
    if (method === "GET" && path === "/v1/state") return json(await service.state(customerId));
    if (method === "POST" && path === "/v1/deposits") {
      return json(await service.createDeposit(customerId, await readBody(request)), 201);
    }
    let m = path.match(/^\/v1\/deposits\/([^/]+)\/days\/([^/]+)$/);
    if (method === "POST" && m) {
      return json(await service.reportDay(customerId, decodeURIComponent(m[1]), decodeURIComponent(m[2]), await readBody(request)));
    }
    m = path.match(/^\/v1\/deposits\/([^/]+)\/renew$/);
    if (method === "POST" && m) {
      return json(await service.setRenew(customerId, decodeURIComponent(m[1]), await readBody(request)));
    }
    throw new HttpError(404, "not_found", "見つかりません");
  } catch (error) {
    return errorResponse(error);
  }
}

/** Cron の見回り */
export async function scheduled(env, deps = {}) {
  const cfg = readConfig(env);
  if (!publicConfig(cfg).ready) return [];
  const stripe = deps.stripe ?? stripeClient(cfg.secretKey, deps.fetch);
  const now = deps.now ?? (() => Math.floor(Date.now() / 1000));
  return depositService({ stripe, cfg, now }).renewDue();
}

export default {
  fetch: (request, env) => handle(request, env),
  scheduled: (_event, env, ctx) => {
    ctx.waitUntil(
      scheduled(env).then(
        (results) => console.log(JSON.stringify({ renewed: results })),
        (error) => console.error("renew failed", error),
      ),
    );
  },
};
