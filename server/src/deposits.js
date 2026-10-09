// 預け金のしくみ(先に7日分を預けて、達成した日の分を返す)。
//
// 台帳は持たず、Stripe の PaymentIntent(預けた支払い)と Refund(返した分)だけを正にする:
//   - 預け金 1 回 = PaymentIntent 1 件。metadata に 1日の額・7日分の日付・各日の始まり・終わり・自動で続けるかを書く
//   - 達成した日の返金 = Refund 1 件。metadata.day にその日の日付(同じ日は二度返さない)
//   - 次の週への自動の預け = 前の PaymentIntent の metadata.next に、新しい PaymentIntent の id
// 返金するかどうかの判定(その日を達成したか)はアプリが行い、サーバーは額と日付の筋だけを確かめる。

import { StripeError } from "./stripe.js";
import { makeToken } from "./auth.js";

export const DAY = 86400;

/** 返金する結果(アプリの CycleOutcome)。一時停止(paused)と未達成(missed)は返さない */
export const REFUNDABLE = new Set(["achieved", "minimum", "pendingReview", "rest", "noCommit", "notStarted"]);

/** 自動で次の週を預けるのは、前の週が終わってからこの時間のうちだけ(遅れて過ぎた日を預け金にしない) */
export const RENEW_WINDOW = 12 * 3600;

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

function int(value, fallback) {
  const n = Number.parseInt(value ?? "", 10);
  return Number.isFinite(n) ? n : fallback;
}

/** wrangler.toml の vars と secrets から設定を読む */
export function readConfig(env = {}) {
  return {
    secretKey: env.STRIPE_SECRET_KEY || "",
    publishableKey: env.STRIPE_PUBLISHABLE_KEY || "",
    tokenSecret: env.TOKEN_SECRET || "",
    registrationCode: env.REGISTRATION_CODE || "",
    minDaily: int(env.MIN_DAILY_YEN, 100),
    maxDaily: int(env.MAX_DAILY_YEN, 3000),
    graceDays: int(env.GRACE_DAYS, 7),
    days: 7,
    merchantName: env.MERCHANT_NAME || "合格ロック",
  };
}

/** アプリに見せてよい設定 */
export function publicConfig(cfg) {
  return {
    ready: Boolean(cfg.secretKey && cfg.publishableKey && cfg.tokenSecret),
    publishableKey: cfg.publishableKey,
    testMode: cfg.publishableKey.startsWith("pk_test_"),
    currency: "jpy",
    minDaily: cfg.minDaily,
    maxDaily: cfg.maxDaily,
    days: cfg.days,
    graceDays: cfg.graceDays,
    merchantName: cfg.merchantName,
    requiresCode: Boolean(cfg.registrationCode),
  };
}

// MARK: 日付

const KEY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** "2026-10-11" に n 日足す(暦の日付として。時差には関係しない) */
export function shiftKey(key, days) {
  const m = KEY.exec(key);
  if (!m) throw new Error(`日付の形がちがいます: ${key}`);
  const date = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + days));
  return date.toISOString().slice(0, 10);
}

/** アプリから届いた 7 日分の予定を確かめる */
export function validatePlan(body, now, cfg) {
  const daily = Number(body?.daily);
  if (!Number.isInteger(daily) || daily < cfg.minDaily || daily > cfg.maxDaily) {
    throw new HttpError(400, "daily_out_of_range", `1日の額は ${cfg.minDaily}〜${cfg.maxDaily} 円にしてください`);
  }
  const days = body?.days;
  if (!Array.isArray(days) || days.length !== cfg.days) {
    throw new HttpError(400, "bad_days", `${cfg.days} 日分の日付を送ってください`);
  }
  const keys = days.map((d) => String(d?.key ?? ""));
  const starts = days.map((d) => Number(d?.startsAt));
  if (keys.some((k) => !KEY.test(k))) throw new HttpError(400, "bad_days", "日付の形がちがいます");
  for (let i = 1; i < keys.length; i++) {
    if (shiftKey(keys[i - 1], 1) !== keys[i]) throw new HttpError(400, "bad_days", "日付が1日ずつ続いていません");
  }
  if (starts.some((s) => !Number.isInteger(s))) throw new HttpError(400, "bad_days", "日の始まりの時刻がありません");
  const ends = Number(body?.endsAt);
  const bounds = [...starts, ends];
  for (let i = 1; i < bounds.length; i++) {
    const gap = bounds[i] - bounds[i - 1];
    // 1日は 23〜25 時間(夏時間の切りかえを許す)
    if (!Number.isInteger(gap) || gap < 23 * 3600 || gap > 25 * 3600) {
      throw new HttpError(400, "bad_days", "1日の長さがおかしい日があります");
    }
  }
  if (starts[0] < now - 10 * 60) throw new HttpError(400, "starts_in_past", "もう始まっている日は、預け金に入れられません");
  if (starts[0] > now + 8 * DAY) throw new HttpError(400, "too_far", "預け金は、1週間以内に始まる日からにしてください");
  return { daily, keys, starts, ends, renew: body?.renew !== false };
}

export function planMetadata(plan, extra = {}) {
  return {
    app: "goukakulock",
    kind: "deposit",
    v: "1",
    daily: String(plan.daily),
    keys: plan.keys.join(","),
    starts: plan.starts.join(","),
    ends: String(plan.ends),
    renew: plan.renew ? "on" : "off",
    ...extra,
  };
}

/** PaymentIntent の metadata から予定を読む(預け金でなければ null) */
export function readPlan(pi) {
  const m = pi?.metadata ?? {};
  if (m.kind !== "deposit" || m.app !== "goukakulock") return null;
  const keys = (m.keys || "").split(",").filter(Boolean);
  const starts = (m.starts || "").split(",").filter(Boolean).map(Number);
  if (keys.length === 0 || keys.length !== starts.length) return null;
  return {
    daily: Number(m.daily),
    keys,
    starts,
    ends: Number(m.ends),
    renew: m.renew === "on",
    next: m.next || null,
    prev: m.prev || null,
    renewError: m.renew_error || null,
  };
}

const liveRefunds = (refunds) => refunds.filter((r) => r.status !== "failed" && r.status !== "canceled");

/** アプリに返す預け金の様子 */
export function depositView(pi, refunds, now, cfg) {
  const plan = readPlan(pi);
  const live = liveRefunds(refunds);
  const byDay = new Map();
  for (const r of live) {
    const day = r.metadata?.day;
    if (day && !byDay.has(day)) byDay.set(day, r);
  }
  const days = plan.keys.map((key, i) => {
    const r = byDay.get(key);
    return {
      key,
      startsAt: plan.starts[i],
      endsAt: i + 1 < plan.starts.length ? plan.starts[i + 1] : plan.ends,
      refunded: Boolean(r),
      refundedAmount: r ? r.amount : 0,
      outcome: r?.metadata?.outcome ?? null,
      refundStatus: r?.status ?? null,
    };
  });
  const refunded = live.reduce((sum, r) => sum + r.amount, 0);
  const closesAt = plan.ends + cfg.graceDays * DAY;
  let status;
  if (pi.status !== "succeeded") status = "pending";
  else if (now < plan.starts[0]) status = "upcoming";
  else if (now < plan.ends) status = "active";
  else if (now < closesAt) status = "ended";
  else status = "closed";
  return {
    id: pi.id,
    status,
    paymentStatus: pi.status,
    daily: plan.daily,
    total: pi.amount,
    currency: pi.currency,
    days,
    refunded,
    forfeited: status === "closed" ? Math.max(0, pi.amount - refunded) : null,
    startsAt: plan.starts[0],
    endsAt: plan.ends,
    closesAt,
    renew: plan.renew,
    next: plan.next,
    prev: plan.prev,
    renewError: plan.renewError,
    createdAt: pi.created,
    livemode: Boolean(pi.livemode),
  };
}

async function listAllRefunds(stripe, piId) {
  const all = [];
  let startingAfter;
  for (let page = 0; page < 5; page++) {
    const res = await stripe.listRefunds({ payment_intent: piId, limit: 100, starting_after: startingAfter });
    all.push(...res.data);
    if (!res.has_more || res.data.length === 0) break;
    startingAfter = res.data[res.data.length - 1].id;
  }
  return all;
}

/**
 * 預け金の窓口
 * @param {{ stripe: ReturnType<import("./stripe.js").stripeClient>, cfg: ReturnType<typeof readConfig>, now: () => number }} deps
 */
export function depositService({ stripe, cfg, now }) {
  async function owned(customerId, piId) {
    if (!/^pi_[A-Za-z0-9]+$/.test(piId)) throw new HttpError(404, "not_found", "預け金が見つかりません");
    let pi;
    try {
      pi = await stripe.retrievePaymentIntent(piId);
    } catch (error) {
      if (error instanceof StripeError && error.status === 404) throw new HttpError(404, "not_found", "預け金が見つかりません");
      throw error;
    }
    if (pi.customer !== customerId || !readPlan(pi)) throw new HttpError(404, "not_found", "預け金が見つかりません");
    return pi;
  }

  async function view(pi) {
    return depositView(pi, await listAllRefunds(stripe, pi.id), now(), cfg);
  }

  /** 前の週が終わった預け金を、保存したカードで次の週へ(自動で続ける) */
  async function renewOne(pi) {
    const plan = readPlan(pi);
    const t = now();
    if (t >= plan.ends + RENEW_WINDOW) {
      await stripe.updatePaymentIntent(pi.id, { metadata: { renew_error: "late" } });
      return { from: pi.id, error: "late" };
    }
    if (!pi.payment_method) {
      await stripe.updatePaymentIntent(pi.id, { metadata: { renew_error: "no_payment_method" } });
      return { from: pi.id, error: "no_payment_method" };
    }
    const next = {
      daily: plan.daily,
      keys: plan.keys.map((k) => shiftKey(k, plan.keys.length)),
      starts: plan.starts.map((s) => s + plan.keys.length * DAY),
      ends: plan.ends + plan.keys.length * DAY,
      renew: true,
    };
    // 次の週に、自分で預け直したものがすでにあれば、それを続きとみなす(二重に預けない)
    const existing = await stripe.listPaymentIntents({ customer: pi.customer, limit: 40 });
    const overlapping = existing.data.find((other) => {
      const p = readPlan(other);
      return other.id !== pi.id && p && (other.status === "succeeded" || other.status === "processing")
        && p.keys.some((k) => next.keys.includes(k));
    });
    if (overlapping) {
      await stripe.updatePaymentIntent(pi.id, { metadata: { next: overlapping.id } });
      return { from: pi.id, to: overlapping.id, status: "already" };
    }
    try {
      const created = await stripe.createPaymentIntent(
        {
          amount: next.daily * next.keys.length,
          currency: pi.currency || "jpy",
          customer: pi.customer,
          payment_method: pi.payment_method,
          payment_method_types: ["card"],
          off_session: true,
          confirm: true,
          description: `合格ロックの預け金(${next.keys[0]}〜${next.keys[next.keys.length - 1]}・自動で続ける)`,
          metadata: planMetadata(next, { prev: pi.id }),
        },
        { idempotencyKey: `goukaku-renew-${pi.id}` },
      );
      await stripe.updatePaymentIntent(pi.id, { metadata: { next: created.id } });
      return { from: pi.id, to: created.id, status: created.status };
    } catch (error) {
      if (error instanceof StripeError && error.status === 402) {
        // カードが通らない・本人確認(3D セキュア)が要る:アプリで預け直してもらう
        await stripe.updatePaymentIntent(pi.id, { metadata: { renew_error: error.code || "card_error" } });
        return { from: pi.id, error: error.code || "card_error" };
      }
      throw error;
    }
  }

  return {
    async register(body) {
      if (cfg.registrationCode && body?.code !== cfg.registrationCode) {
        throw new HttpError(403, "bad_code", "招待コードがちがいます");
      }
      const customer = await stripe.createCustomer({
        description: "合格ロックの預け金",
        metadata: { app: "goukakulock" },
      });
      return { token: await makeToken(cfg.tokenSecret, customer.id), customerId: customer.id };
    },

    async state(customerId) {
      const list = await stripe.listPaymentIntents({ customer: customerId, limit: 40 });
      const paid = list.data.filter((pi) => readPlan(pi) && (pi.status === "succeeded" || pi.status === "processing"));
      const deposits = [];
      for (const pi of paid) deposits.push(await view(pi));
      deposits.sort((a, b) => b.startsAt - a.startsAt);
      return { deposits: deposits.slice(0, 10), now: now(), config: publicConfig(cfg) };
    },

    async createDeposit(customerId, body) {
      const plan = validatePlan(body, now(), cfg);
      const existing = await stripe.listPaymentIntents({ customer: customerId, limit: 40 });
      for (const pi of existing.data) {
        const p = readPlan(pi);
        if (!p) continue;
        if (pi.status === "succeeded" || pi.status === "processing") {
          if (p.keys.some((k) => plan.keys.includes(k))) {
            throw new HttpError(409, "overlap", "この日にちには、もう預け金があります");
          }
        } else if (pi.status.startsWith("requires_")) {
          // 途中でやめた前の預け金は取り消す(あとから払われて重ならないように)
          await stripe.cancelPaymentIntent(pi.id).catch(() => {});
        }
      }
      const pi = await stripe.createPaymentIntent({
        amount: plan.daily * plan.keys.length,
        currency: "jpy",
        customer: customerId,
        payment_method_types: ["card"],
        setup_future_usage: "off_session",
        description: `合格ロックの預け金(${plan.keys[0]}〜${plan.keys[plan.keys.length - 1]})`,
        metadata: planMetadata(plan),
      });
      return {
        depositId: pi.id,
        clientSecret: pi.client_secret,
        amount: pi.amount,
        publishableKey: cfg.publishableKey,
        merchantName: cfg.merchantName,
      };
    },

    async reportDay(customerId, piId, key, body) {
      const outcome = String(body?.outcome ?? "");
      if (!REFUNDABLE.has(outcome)) throw new HttpError(400, "not_refundable", "この日の結果では返金しません");
      const pi = await owned(customerId, piId);
      if (pi.status !== "succeeded") throw new HttpError(409, "not_paid", "まだ支払いが終わっていません");
      const plan = readPlan(pi);
      const index = plan.keys.indexOf(key);
      if (index < 0) throw new HttpError(404, "unknown_day", "この預け金の日ではありません");
      const t = now();
      if (t < plan.starts[index]) throw new HttpError(409, "too_early", "まだ始まっていない日です");
      if (t >= plan.ends + cfg.graceDays * DAY) throw new HttpError(410, "closed", "返金の受付を締め切りました");
      let refunds = await listAllRefunds(stripe, piId);
      const live = liveRefunds(refunds);
      if (!live.some((r) => r.metadata?.day === key)) {
        const remaining = pi.amount - live.reduce((sum, r) => sum + r.amount, 0);
        const amount = Math.min(plan.daily, remaining);
        if (amount > 0) {
          await stripe.createRefund(
            { payment_intent: piId, amount, reason: "requested_by_customer", metadata: { app: "goukakulock", day: key, outcome } },
            { idempotencyKey: `goukaku-refund-${piId}-${key}` },
          );
          refunds = await listAllRefunds(stripe, piId);
        }
      }
      return depositView(pi, refunds, t, cfg);
    },

    async setRenew(customerId, piId, body) {
      await owned(customerId, piId);
      const on = body?.on === true;
      // 「止める」はいつでも。「続ける」に戻したら、前の失敗の印も消す
      const updated = await stripe.updatePaymentIntent(piId, { metadata: { renew: on ? "on" : "off", renew_error: "" } });
      return view(updated);
    },

    /** 定期の見回り(Cron):週が終わった預け金のうち、自動で続けるものを次の週へ */
    async renewDue() {
      const results = [];
      let page;
      for (let round = 0; round < 20; round++) {
        const res = await stripe.searchPaymentIntents({
          query: "metadata['kind']:'deposit' AND metadata['renew']:'on' AND status:'succeeded'",
          limit: 100,
          page,
        });
        for (const pi of res.data) {
          const plan = readPlan(pi);
          if (!plan || plan.next || plan.renewError || !plan.renew) continue;
          if (now() < plan.ends) continue;
          try {
            results.push(await renewOne(pi));
          } catch (error) {
            results.push({ from: pi.id, error: error.message });
          }
        }
        if (!res.has_more || !res.next_page) break;
        page = res.next_page;
      }
      return results;
    },
  };
}
