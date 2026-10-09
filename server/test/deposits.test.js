import { test } from "node:test";
import assert from "node:assert/strict";
import { handle, scheduled } from "../src/index.js";
import { encodeForm } from "../src/stripe.js";
import { makeToken, readToken } from "../src/auth.js";
import { shiftKey, DAY, RENEW_WINDOW } from "../src/deposits.js";
import { createFakeStripe } from "./fake-stripe.js";

const ENV = {
  STRIPE_SECRET_KEY: "sk_test_fake",
  STRIPE_PUBLISHABLE_KEY: "pk_test_fake",
  TOKEN_SECRET: "token-secret-for-tests",
  MIN_DAILY_YEN: "100",
  MAX_DAILY_YEN: "3000",
  GRACE_DAYS: "7",
};

// 日付切替 4:00(日本時間)の 2026-10-12 から 7 日分
const FIRST_START = Date.UTC(2026, 9, 11, 19, 0, 0) / 1000;
const plan = (first = "2026-10-12", start = FIRST_START, daily = 300, renew = true) => ({
  daily,
  renew,
  days: Array.from({ length: 7 }, (_, i) => ({ key: shiftKey(first, i), startsAt: start + i * DAY })),
  endsAt: start + 7 * DAY,
});

function world(env = ENV) {
  let t = FIRST_START - 3600; // 始まる1時間前
  const stripe = createFakeStripe({ now: () => t });
  const deps = { now: () => t, fetch: stripe.fetch };
  async function call(method, path, { body, token } = {}) {
    const headers = { "Content-Type": "application/json" };
    if (token) headers.Authorization = `Bearer ${token}`;
    const res = await handle(
      new Request(`https://deposit.example${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }),
      env,
      deps,
    );
    return { status: res.status, body: await res.json() };
  }
  return {
    stripe,
    call,
    get now() { return t; },
    set now(v) { t = v; },
    cron: () => scheduled(env, deps),
    async register(body = {}) {
      const r = await call("POST", "/v1/register", { body });
      assert.equal(r.status, 201, JSON.stringify(r.body));
      return r.body.token;
    },
    async deposit(token, p = plan()) {
      const r = await call("POST", "/v1/deposits", { token, body: p });
      assert.equal(r.status, 201, JSON.stringify(r.body));
      return r.body;
    },
    /** アプリがつながった(週の途中で開いた) */
    async seen(token, id, next) {
      const r = await call("POST", `/v1/deposits/${id}/seen`, { token, body: next ? { next } : {} });
      assert.equal(r.status, 200, JSON.stringify(r.body));
      return r.body;
    },
  };
}

test("設定:公開鍵と額の範囲だけを見せ、秘密の鍵は出さない", async () => {
  const w = world();
  const r = await w.call("GET", "/v1/config");
  assert.equal(r.status, 200);
  assert.equal(r.body.ready, true);
  assert.equal(r.body.publishableKey, "pk_test_fake");
  assert.equal(r.body.testMode, true);
  assert.equal(r.body.days, 7);
  assert.equal(r.body.minDaily, 100);
  assert.ok(!JSON.stringify(r.body).includes("sk_test"));
  // 設定が足りないサーバーは、ほかの窓口を開けない
  const empty = world({});
  assert.equal((await empty.call("GET", "/v1/config")).body.ready, false);
  const blocked = await empty.call("POST", "/v1/register", { body: {} });
  assert.equal(blocked.status, 503);
  assert.equal(blocked.body.error.code, "not_configured");
});

test("登録:合い言葉で自分の客だけを扱う。招待コードを決めたサーバーは、コードがいる", async () => {
  const w = world();
  const token = await w.register();
  assert.match(token, /^cus_[a-z0-9]+\./);
  assert.equal((await w.call("GET", "/v1/state", { token })).status, 200);
  assert.equal((await w.call("GET", "/v1/state")).status, 401);
  assert.equal((await w.call("GET", "/v1/state", { token: token.slice(0, -2) + "xx" })).status, 401);
  const invited = world({ ...ENV, REGISTRATION_CODE: "aikotoba" });
  assert.equal((await invited.call("POST", "/v1/register", { body: {} })).status, 403);
  assert.equal((await invited.call("POST", "/v1/register", { body: { code: "aikotoba" } })).status, 201);
});

test("本番モード:招待コードを決めていないサーバーは、だれも登録させない", async () => {
  const live = { ...ENV, STRIPE_SECRET_KEY: "sk_live_fake", STRIPE_PUBLISHABLE_KEY: "pk_live_fake" };
  const w = world(live);
  const config = (await w.call("GET", "/v1/config")).body;
  assert.equal(config.testMode, false);
  assert.equal(config.requiresCode, true);
  const r = await w.call("POST", "/v1/register", { body: {} });
  assert.equal(r.status, 403);
  assert.equal(r.body.error.code, "code_required");
  const coded = world({ ...live, REGISTRATION_CODE: "aikotoba" });
  for (const code of [undefined, "", "aikotob", "aikotobaa"]) {
    const res = await coded.call("POST", "/v1/register", { body: code === undefined ? {} : { code } });
    assert.equal(res.status, 403, String(code));
    assert.equal(res.body.error.code, "bad_code");
  }
  assert.equal((await coded.call("POST", "/v1/register", { body: { code: "aikotoba" } })).status, 201);
});

test("トークン:署名がちがえば読めない", async () => {
  const token = await makeToken("s", "cus_abc");
  assert.equal(await readToken("s", token), "cus_abc");
  assert.equal(await readToken("other", token), null);
  assert.equal(await readToken("s", "cus_abd" + token.slice(7)), null);
  assert.equal(await readToken("s", "nonsense"), null);
});

test("預ける → 払う → 達成した日の分だけ返る → 締め切ったら戻らない分が決まる", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  assert.equal(created.amount, 2100);
  assert.match(created.clientSecret, /^pi_.*_secret_/);
  assert.equal(created.publishableKey, "pk_test_fake");
  const pi = w.stripe.intents.get(created.depositId);
  assert.equal(pi.setup_future_usage, "off_session", "次の週のためにカードを保存する");
  assert.equal(pi.currency, "jpy");

  // 払う前は、預け金として数えない
  assert.deepEqual((await w.call("GET", "/v1/state", { token })).body.deposits, []);
  w.stripe.pay(created.depositId);
  let state = (await w.call("GET", "/v1/state", { token })).body;
  assert.equal(state.deposits.length, 1);
  assert.equal(state.deposits[0].status, "upcoming");
  assert.equal(state.deposits[0].total, 2100);
  assert.equal(state.deposits[0].days.length, 7);

  // 始まる前の日は返せない
  const early = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-12`, { token, body: { outcome: "achieved" } });
  assert.equal(early.status, 409);
  assert.equal(early.body.error.code, "too_early");

  // 1日目を達成 → 300 円返る。同じ日をもう一度知らせても、二度は返さない
  w.now = FIRST_START + 20 * 3600;
  for (let i = 0; i < 2; i++) {
    const r = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-12`, { token, body: { outcome: "achieved" } });
    assert.equal(r.status, 200, JSON.stringify(r.body));
    assert.equal(r.body.refunded, 300);
    assert.equal(r.body.status, "active");
    assert.equal(r.body.days[0].refunded, true);
    assert.equal(r.body.days[0].outcome, "achieved");
  }
  assert.equal([...w.stripe.refunds.values()].length, 1);
  const refund = [...w.stripe.refunds.values()][0];
  assert.equal(refund.amount, 300);
  assert.equal(refund.metadata.day, "2026-10-12");

  // 未達成・一時停止・事後承認待ちの日は返さない(アプリも知らせないが、来ても受けない)
  w.now = FIRST_START + DAY + 3600;
  for (const outcome of ["missed", "paused", "pendingReview", "", "achievedd"]) {
    const r = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-13`, { token, body: { outcome } });
    assert.equal(r.status, 400, outcome);
    assert.equal(r.body.error.code, "not_refundable");
  }
  // 最小版・休養日・予定のない日は返す
  w.now = FIRST_START + 4 * DAY;
  for (const [key, outcome] of [["2026-10-14", "minimum"], ["2026-10-15", "rest"], ["2026-10-16", "noCommit"]]) {
    const r = await w.call("POST", `/v1/deposits/${created.depositId}/days/${key}`, { token, body: { outcome } });
    assert.equal(r.status, 200, `${key} ${JSON.stringify(r.body)}`);
  }
  // 預け金にない日
  const unknown = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-30`, { token, body: { outcome: "achieved" } });
  assert.equal(unknown.status, 404);

  // 週が終わったあとも、受付の期間(7日)は知らせを受ける
  w.now = FIRST_START + 7 * DAY + 3 * DAY;
  const late = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-18`, { token, body: { outcome: "achieved" } });
  assert.equal(late.status, 200);
  assert.equal(late.body.status, "ended");
  assert.equal(late.body.refunded, 1500);
  assert.equal(late.body.forfeited, null, "締め切るまでは、戻らない額は決まらない");

  // 締め切ったら、もう返さない。戻らない額が決まる
  w.now = FIRST_START + 14 * DAY + 1;
  const closed = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-17`, { token, body: { outcome: "achieved" } });
  assert.equal(closed.status, 410);
  state = (await w.call("GET", "/v1/state", { token })).body;
  assert.equal(state.deposits[0].status, "closed");
  assert.equal(state.deposits[0].forfeited, 600);
  assert.deepEqual(state.deposits[0].days.map((d) => d.refunded), [true, false, true, true, true, false, true]);
});

test("預ける予定の確かめ:額の範囲・7日・続いた日付・始まった日は入れない", async () => {
  const w = world();
  const token = await w.register();
  const bad = async (body, code) => {
    const r = await w.call("POST", "/v1/deposits", { token, body });
    assert.equal(r.status, 400, JSON.stringify(r.body));
    assert.equal(r.body.error.code, code);
  };
  await bad(plan(undefined, undefined, 50), "daily_out_of_range");
  await bad(plan(undefined, undefined, 5000), "daily_out_of_range");
  await bad(plan(undefined, undefined, 150.5), "daily_out_of_range");
  await bad({ ...plan(), days: plan().days.slice(0, 6) }, "bad_days");
  const gap = plan();
  gap.days[3].key = "2026-10-20";
  await bad(gap, "bad_days");
  const longDay = plan();
  longDay.days[2].startsAt += 5 * 3600;
  await bad(longDay, "bad_days");
  const notADate = plan();
  notADate.days[0].key = "2027-02-30";
  await bad(notADate, "bad_days");
  await bad(plan("2020-01-01"), "bad_days");
  w.now = FIRST_START + 3600;
  await bad(plan(), "starts_in_past");
  w.now = FIRST_START - 9 * DAY;
  await bad(plan(), "too_far");
});

test("同じ日に二重に預けない。途中でやめた支払いは取り消す。自動で続く予定の週は預けない", async () => {
  const w = world();
  const token = await w.register();
  const abandoned = await w.deposit(token);
  const paid = await w.deposit(token);
  assert.equal(w.stripe.intents.get(abandoned.depositId).status, "canceled");
  w.stripe.pay(paid.depositId);
  const again = await w.call("POST", "/v1/deposits", { token, body: plan() });
  assert.equal(again.status, 409);
  assert.equal(again.body.error.code, "overlap");
  // 次の週は、前の週から自動で続く予定なので、自分では預けられない(二重に払わないように)
  const nextWeek = plan("2026-10-19", FIRST_START + 7 * DAY);
  const renews = await w.call("POST", "/v1/deposits", { token, body: nextWeek });
  assert.equal(renews.status, 409);
  assert.equal(renews.body.error.code, "renews");
  // 自動で続けるのを止めれば、自分で預けられる
  const off = await w.call("POST", `/v1/deposits/${paid.depositId}/renew`, { token, body: { on: false } });
  assert.equal(off.body.renew, false);
  const next = await w.call("POST", "/v1/deposits", { token, body: nextWeek });
  assert.equal(next.status, 201);
});

test("ほかの人の預け金には触れない", async () => {
  const w = world();
  const mine = await w.register();
  const other = await w.register();
  const created = await w.deposit(mine);
  w.stripe.pay(created.depositId);
  w.now = FIRST_START + 3600;
  const r = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-12`, { token: other, body: { outcome: "achieved" } });
  assert.equal(r.status, 404);
  for (const [path, body] of [["renew", { on: false }], ["seen", {}], ["cancel", {}]]) {
    const res = await w.call("POST", `/v1/deposits/${created.depositId}/${path}`, { token: other, body });
    assert.equal(res.status, 404, path);
  }
  assert.equal((await w.call("POST", "/v1/deposits/nope/renew", { token: mine, body: { on: false } })).status, 404);
  // 何も変わっていない
  const pi = w.stripe.intents.get(created.depositId);
  assert.equal(pi.metadata.renew, "on");
  assert.equal(pi.metadata.seen, undefined);
  assert.equal(pi.metadata.canceled_at, undefined);
  assert.equal(w.stripe.refunds.size, 0);
});

test("自動で続ける:その週にアプリがつながっていれば、週が終わると保存したカードで次の7日分を預ける(二重にしない)", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);

  w.now = FIRST_START + 3 * DAY;
  const seen = await w.seen(token, created.depositId);
  assert.equal(seen.seenAt, FIRST_START + 3 * DAY);
  const updates = () => w.stripe.calls.filter((c) => c.method === "POST" && c.path === `/payment_intents/${created.depositId}`).length;
  const before = updates();
  w.now += 3600;
  await w.seen(token, created.depositId);
  assert.equal(updates(), before, "しばらくは、つながった印を書き直さない");
  assert.deepEqual(await w.cron(), [], "週の途中では何もしない");

  w.now = FIRST_START + 7 * DAY + 900;
  const results = await w.cron();
  assert.equal(results.length, 1);
  assert.equal(results[0].from, created.depositId);
  assert.equal(results[0].status, "succeeded");
  const next = w.stripe.intents.get(results[0].to);
  assert.equal(next.amount, 2100);
  assert.equal(next.metadata.prev, created.depositId);
  assert.equal(next.metadata.keys.split(",")[0], "2026-10-19");
  assert.equal(Number(next.metadata.starts.split(",")[0]), FIRST_START + 7 * DAY);
  assert.equal(next.metadata.renew, "on", "新しい週も続ける");
  assert.equal(next.metadata.seen, undefined, "新しい週は、その週につながったら印がつく");
  const old = w.stripe.intents.get(created.depositId);
  assert.equal(next.payment_method, old.payment_method, "同じカード");
  assert.equal(old.metadata.next, next.id);
  assert.equal(old.metadata.renew, "done", "前の週は、もう見回りの対象にしない");
  assert.deepEqual(await w.cron(), [], "もう一度回っても、二重に預けない");

  const state = (await w.call("GET", "/v1/state", { token })).body;
  assert.equal(state.deposits[0].id, next.id, "新しい週が先");
  assert.equal(state.deposits[0].status, "active");
  assert.equal(state.deposits[0].renew, true);
  assert.equal(state.deposits[1].next, next.id);
  assert.equal(state.deposits[1].renew, false);
});

test("自動で続ける:その週に一度もアプリがつながらなかったら、勝手には続けない", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  // 始まる前につながっただけでは足りない(合い言葉をなくした・iPhone を替えた などで、預けたまま知らせられなくなるため)
  await w.seen(token, created.depositId);
  w.now = FIRST_START + 7 * DAY + 60;
  const results = await w.cron();
  assert.equal(results[0].error, "inactive");
  assert.equal(w.stripe.intents.size, 1, "新しい支払いは作らない");
  const state = (await w.call("GET", "/v1/state", { token })).body;
  assert.equal(state.deposits[0].renewError, "inactive");
  assert.deepEqual(await w.cron(), []);
});

test("自動で続ける:検索のあとで止めた(検索は少し遅れる)なら、読み直して続けない", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  w.now = FIRST_START + DAY;
  await w.seen(token, created.depositId);
  w.now = FIRST_START + 7 * DAY + 60;
  // 検索が「続ける」の写しを返したあとで、アプリが止めた
  w.stripe.hooks.afterSearch = () => {
    w.stripe.intents.get(created.depositId).metadata.renew = "off";
  };
  const results = await w.cron();
  assert.equal(results[0].skipped, "changed");
  assert.equal(w.stripe.intents.size, 1, "新しい支払いは作らない");
});

test("自動で続ける:次の週の日の始まりは、アプリが知らせたもの(日付切替の変更・夏時間)を使う", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  w.now = FIRST_START + 2 * DAY;
  const send = (p) => w.call("POST", `/v1/deposits/${created.depositId}/seen`, { token, body: { next: { days: p.days, endsAt: p.endsAt } } });
  // 日付がちがう・この週の終わりから離れすぎている
  for (const wrong of [plan("2026-10-20", FIRST_START + 8 * DAY), plan("2026-10-19", FIRST_START + 7 * DAY + 8 * 3600)]) {
    const r = await send(wrong);
    assert.equal(r.status, 400, JSON.stringify(r.body));
    assert.equal(r.body.error.code, "bad_days");
  }
  // 日付切替を 4:00 から 5:00 に変えた
  const shifted = plan("2026-10-19", FIRST_START + 7 * DAY + 3600);
  await w.seen(token, created.depositId, { days: shifted.days, endsAt: shifted.endsAt });
  w.now = FIRST_START + 7 * DAY + 60;
  const results = await w.cron();
  const next = w.stripe.intents.get(results[0].to);
  assert.deepEqual(next.metadata.starts.split(",").map(Number), shifted.days.map((d) => d.startsAt));
  assert.equal(Number(next.metadata.ends), shifted.endsAt);
});

test("自動で続ける:止めた人は続けない。カードの確認が要る・通らない・外されたときは印をつけ、アプリで預け直してもらう", async () => {
  const w = world();
  const token = await w.register();
  const stopped = await w.deposit(token);
  w.stripe.pay(stopped.depositId);
  w.now = FIRST_START + DAY;
  await w.seen(token, stopped.depositId);
  const off = await w.call("POST", `/v1/deposits/${stopped.depositId}/renew`, { token, body: { on: false } });
  assert.equal(off.status, 200);
  assert.equal(off.body.renew, false);
  w.now = FIRST_START + 7 * DAY + 60;
  assert.deepEqual(await w.cron(), []);

  async function failing(card) {
    const f = world();
    const token = await f.register();
    const created = await f.deposit(token);
    f.stripe.pay(created.depositId, card);
    f.now = FIRST_START + DAY;
    await f.seen(token, created.depositId);
    f.now = FIRST_START + 7 * DAY + 60;
    return { f, token, created, results: await f.cron() };
  }

  // カードの確認(3D セキュア)が要る
  const auth = await failing({ requiresAuth: true });
  const id = auth.created.depositId;
  assert.equal(auth.results[0].error, "authentication_required");
  const state = (await auth.f.call("GET", "/v1/state", { token: auth.token })).body;
  assert.equal(state.deposits[0].renewError, "authentication_required");
  assert.deepEqual(await auth.f.cron(), [], "失敗の印があるあいだは、くり返し請求しない");
  // 「続ける」をもう一度オンにすると、印が消え、新しい鍵でやり直す(前の確認待ちの支払いは取り消してから)
  const on = await auth.f.call("POST", `/v1/deposits/${id}/renew`, { token: auth.token, body: { on: true } });
  assert.equal(on.body.renewError, null);
  assert.equal(on.body.renew, true);
  assert.equal((await auth.f.cron())[0].error, "authentication_required");
  const keys = auth.f.stripe.calls
    .filter((c) => c.method === "POST" && c.path === "/payment_intents" && c.params.confirm === "true")
    .map((c) => c.headers["Idempotency-Key"]);
  assert.deepEqual(keys, [`goukaku-renew-${id}`, `goukaku-renew-${id}-try1`]);
  const attempts = [...auth.f.stripe.intents.values()].filter((pi) => pi.metadata.prev === id);
  assert.deepEqual(attempts.map((pi) => pi.status), ["canceled", "requires_action"]);

  // カードが通らない・カードが外された
  assert.equal((await failing({ declines: true })).results[0].error, "card_declined");
  assert.equal((await failing({ detached: true })).results[0].error, "payment_method_unexpected_state");
});

test("自動で続ける:見回りが遅れて半日以上たったら、過ぎた日を預け金にしない", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  w.now = FIRST_START + DAY;
  await w.seen(token, created.depositId);
  w.now = FIRST_START + 7 * DAY + RENEW_WINDOW + 1;
  const results = await w.cron();
  assert.equal(results[0].error, "late");
  assert.equal(w.stripe.intents.get(created.depositId).metadata.renew_error, "late");
  assert.equal(w.stripe.intents.size, 1, "新しい支払いは作らない");
});

test("自動で続ける:次の週を自分で預けていたら、それを続きにする。払いかけのものは取り消してから預ける", async () => {
  const w = world();
  const token = await w.register();
  const first = await w.deposit(token, plan(undefined, undefined, 300, false));
  w.stripe.pay(first.depositId);
  const manual = await w.deposit(token, plan("2026-10-19", FIRST_START + 7 * DAY));
  w.stripe.pay(manual.depositId);
  // あとから「続ける」を入れた
  await w.call("POST", `/v1/deposits/${first.depositId}/renew`, { token, body: { on: true } });
  w.now = FIRST_START + DAY;
  await w.seen(token, first.depositId);
  w.now = FIRST_START + 7 * DAY + 60;
  const results = await w.cron();
  assert.equal(results.length, 1);
  assert.equal(results[0].to, manual.depositId);
  assert.equal(results[0].status, "already");
  assert.equal([...w.stripe.intents.values()].filter((pi) => pi.status === "succeeded").length, 2, "請求は増えない");
  assert.equal(w.stripe.intents.get(first.depositId).metadata.renew, "done");

  // 次の週を自分で払いかけてやめていた
  const w2 = world();
  const token2 = await w2.register();
  const first2 = await w2.deposit(token2, plan(undefined, undefined, 300, false));
  w2.stripe.pay(first2.depositId);
  const abandoned = await w2.deposit(token2, plan("2026-10-19", FIRST_START + 7 * DAY));
  await w2.call("POST", `/v1/deposits/${first2.depositId}/renew`, { token: token2, body: { on: true } });
  w2.now = FIRST_START + DAY;
  await w2.seen(token2, first2.depositId);
  w2.now = FIRST_START + 7 * DAY + 60;
  const results2 = await w2.cron();
  assert.equal(results2[0].status, "succeeded");
  assert.equal(w2.stripe.intents.get(abandoned.depositId).status, "canceled", "あとから払われて二重にならないように");
});

test("やめる:まだ始まっていない日の分を返し、自動で続けるのも止める。今日までは結果しだい", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  // 1日目を達成して返金ずみ。3日目の昼にやめる
  w.now = FIRST_START + 3600;
  await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-12`, { token, body: { outcome: "achieved" } });
  w.now = FIRST_START + 2 * DAY + 12 * 3600;
  await w.seen(token, created.depositId);
  const r = await w.call("POST", `/v1/deposits/${created.depositId}/cancel`, { token });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.renew, false);
  assert.equal(r.body.canceledAt, w.now);
  assert.deepEqual(r.body.days.map((d) => d.refunded), [true, false, false, true, true, true, true]);
  assert.deepEqual(r.body.days.slice(3).map((d) => d.outcome), ["canceled", "canceled", "canceled", "canceled"]);
  assert.equal(r.body.refunded, 300 + 4 * 300);
  // 今日(3日目)は、達成すればこれまでどおり返る。もう一度やめても増えない
  const today = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-14`, { token, body: { outcome: "achieved" } });
  assert.equal(today.body.refunded, 1800);
  const again = await w.call("POST", `/v1/deposits/${created.depositId}/cancel`, { token });
  assert.equal(again.body.refunded, 1800);
  // やめた週から「続ける」には戻せない
  const on = await w.call("POST", `/v1/deposits/${created.depositId}/renew`, { token, body: { on: true } });
  assert.equal(on.status, 409);
  assert.equal(on.body.error.code, "canceled");
  // 週が終わっても、自動では続けない
  w.now = FIRST_START + 7 * DAY + 60;
  assert.deepEqual(await w.cron(), []);
});

test("やめる:返金がうまくいかなくても、自動で続けるのは先に止まっている", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  w.now = FIRST_START + DAY;
  await w.seen(token, created.depositId);
  w.stripe.hooks.failRefunds = true;
  const r = await w.call("POST", `/v1/deposits/${created.depositId}/cancel`, { token });
  assert.equal(r.status, 502);
  assert.equal(w.stripe.intents.get(created.depositId).metadata.renew, "off");
  // あとでもう一度やめると、そのときまだ始まっていない日の分が返る
  w.stripe.hooks.failRefunds = false;
  w.now = FIRST_START + 2 * DAY + 3600;
  const retry = await w.call("POST", `/v1/deposits/${created.depositId}/cancel`, { token });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.refunded, 4 * 300);
  w.now = FIRST_START + 7 * DAY + 60;
  assert.deepEqual(await w.cron(), []);
});

test("返金が失敗していた日は、新しい鍵でやり直す", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token);
  w.stripe.pay(created.depositId);
  w.stripe.addRefund(created.depositId, { day: "2026-10-12", amount: 300, status: "failed" });
  w.now = FIRST_START + 3600;
  const r = await w.call("POST", `/v1/deposits/${created.depositId}/days/2026-10-12`, { token, body: { outcome: "achieved" } });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.refunded, 300, "失敗した返金は数えない");
  assert.equal(r.body.days[0].refundStatus, "succeeded");
  const call = w.stripe.calls.find((c) => c.method === "POST" && c.path === "/refunds");
  assert.equal(call.headers["Idempotency-Key"], `goukaku-refund-${created.depositId}-2026-10-12-retry1`);
});

test("返金は預けた額を超えない", async () => {
  const w = world();
  const token = await w.register();
  const created = await w.deposit(token, plan(undefined, undefined, 100));
  w.stripe.pay(created.depositId);
  w.now = FIRST_START + 7 * DAY;
  let last;
  for (const day of plan().days) {
    last = await w.call("POST", `/v1/deposits/${created.depositId}/days/${day.key}`, { token, body: { outcome: "achieved" } });
    assert.equal(last.status, 200);
  }
  assert.equal(last.body.refunded, 700);
  assert.equal(last.body.total, 700);
});

test("Stripe への送り方:入れ子の metadata と配列", () => {
  assert.equal(
    encodeForm({ amount: 2100, metadata: { day: "2026-10-12", empty: "" }, payment_method_types: ["card"], skip: undefined }),
    "amount=2100&metadata%5Bday%5D=2026-10-12&metadata%5Bempty%5D=&payment_method_types%5B0%5D=card",
  );
});

test("知らない道・まちがった合い言葉", async () => {
  const w = world();
  assert.equal((await w.call("GET", "/")).body.ok, true);
  const token = await w.register();
  assert.equal((await w.call("GET", "/v1/nothing", { token })).status, 404);
  assert.equal((await w.call("POST", "/v1/deposits", { token: "cus_x.zzz", body: plan() })).status, 401);
});
