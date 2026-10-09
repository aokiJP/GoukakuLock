// テスト用の偽の Stripe(使う API だけを、手元のメモリで本物と同じ形に返す)

function decodeForm(text) {
  const out = {};
  if (!text) return out;
  for (const part of text.split("&")) {
    if (!part) continue;
    const [rawKey, rawValue = ""] = part.split("=");
    const key = decodeURIComponent(rawKey.replace(/\+/g, " "));
    const value = decodeURIComponent(rawValue.replace(/\+/g, " "));
    const path = key.replace(/\]/g, "").split("[");
    let node = out;
    for (let i = 0; i < path.length - 1; i++) {
      const name = path[i];
      const nextIsIndex = /^\d+$/.test(path[i + 1]);
      if (!(name in node)) node[name] = nextIsIndex ? [] : {};
      node = node[name];
    }
    const last = path[path.length - 1];
    if (Array.isArray(node)) node[Number(last)] = value;
    else node[last] = value;
  }
  return out;
}

export function createFakeStripe({ now = () => Math.floor(Date.now() / 1000) } = {}) {
  let seq = 0;
  const nextId = (prefix) => `${prefix}_${(++seq).toString(36).padStart(6, "0")}`;
  const customers = new Map();
  const intents = new Map();
  const refunds = new Map();
  const paymentMethods = new Map();
  const idempotency = new Map();
  const calls = [];
  const hooks = {};

  const reply = (status, body) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
  const error = (status, code, message, extra = {}) =>
    reply(status, { error: { code, message, type: status === 402 ? "card_error" : "invalid_request_error", ...extra } });

  function setMetadata(target, metadata) {
    for (const [k, v] of Object.entries(metadata ?? {})) {
      if (v === "") delete target[k];
      else target[k] = String(v);
    }
  }

  function createIntent(params) {
    const id = nextId("pi");
    const pi = {
      id,
      object: "payment_intent",
      amount: Number(params.amount),
      currency: params.currency,
      customer: params.customer ?? null,
      client_secret: `${id}_secret_test`,
      status: "requires_payment_method",
      payment_method: null,
      setup_future_usage: params.setup_future_usage ?? null,
      metadata: {},
      created: now(),
      livemode: false,
    };
    setMetadata(pi.metadata, params.metadata);
    if (params.confirm === "true") {
      const pm = paymentMethods.get(params.payment_method);
      if (!pm) return error(400, "resource_missing", "No such PaymentMethod");
      pi.payment_method = pm.id;
      if (pm.requiresAuth) {
        pi.status = "requires_action";
        intents.set(id, pi);
        return error(402, "authentication_required", "This payment requires authentication.", { payment_intent: pi });
      }
      if (pm.declines) {
        pi.status = "requires_payment_method";
        intents.set(id, pi);
        return error(402, "card_declined", "Your card was declined.", { payment_intent: pi });
      }
      if (pm.detached) {
        return error(400, "payment_method_unexpected_state", "The PaymentMethod is detached.");
      }
      pi.status = "succeeded";
    }
    intents.set(id, pi);
    return reply(200, pi);
  }

  function search(query) {
    // 例: metadata['kind']:'deposit' AND metadata['renew']:'on' AND status:'succeeded'
    const conditions = query.split(/\s+AND\s+/).map((c) => {
      const meta = /^metadata\['([^']+)'\]:'([^']*)'$/.exec(c.trim());
      if (meta) return (pi) => pi.metadata[meta[1]] === meta[2];
      const field = /^(\w+):'([^']*)'$/.exec(c.trim());
      if (field) return (pi) => String(pi[field[1]]) === field[2];
      throw new Error(`偽の Stripe が読めない検索: ${c}`);
    });
    return [...intents.values()].filter((pi) => conditions.every((test) => test(pi))).reverse();
  }

  async function fetchImpl(input, init = {}) {
    const url = new URL(input);
    const method = init.method || "GET";
    const params = method === "GET" ? decodeForm(url.search.slice(1)) : decodeForm(init.body);
    const headers = init.headers || {};
    const path = url.pathname.replace(/^\/v1/, "");
    calls.push({ method, path, params, headers });
    if (!String(headers.Authorization || "").startsWith("Bearer sk_")) return error(401, "auth", "Invalid API Key");

    const key = headers["Idempotency-Key"];
    if (key && idempotency.has(key)) {
      const saved = idempotency.get(key);
      return reply(saved.status, saved.body);
    }
    const remember = async (response) => {
      if (key) idempotency.set(key, { status: response.status, body: await response.clone().json() });
      return response;
    };

    if (method === "POST" && path === "/customers") {
      const id = nextId("cus");
      const customer = { id, object: "customer", metadata: {}, description: params.description ?? null };
      setMetadata(customer.metadata, params.metadata);
      customers.set(id, customer);
      return remember(reply(200, customer));
    }
    if (method === "POST" && path === "/payment_intents") return remember(createIntent(params));
    if (method === "GET" && path === "/payment_intents/search") {
      const all = search(params.query);
      const start = params.page ? Number(params.page) : 0;
      const limit = Number(params.limit || 10);
      const data = all.slice(start, start + limit);
      const hasMore = start + limit < all.length;
      // 検索の結果は、その時点の写し(本物の Search は少し遅れる。hooks.afterSearch で、写したあとに変えられる)
      const response = reply(200, { object: "search_result", data, has_more: hasMore, next_page: hasMore ? String(start + limit) : null });
      hooks.afterSearch?.();
      return response;
    }
    if (method === "GET" && path === "/payment_intents") {
      const data = [...intents.values()].filter((pi) => !params.customer || pi.customer === params.customer).reverse();
      return reply(200, { object: "list", data: data.slice(0, Number(params.limit || 10)), has_more: data.length > Number(params.limit || 10) });
    }
    let m = path.match(/^\/payment_intents\/([^/]+)(\/cancel)?$/);
    if (m) {
      const pi = intents.get(decodeURIComponent(m[1]));
      if (!pi) return error(404, "resource_missing", "No such payment_intent");
      if (method === "GET") return reply(200, pi);
      if (m[2]) {
        if (pi.status === "succeeded") return error(400, "payment_intent_unexpected_state", "Cannot cancel");
        pi.status = "canceled";
        return reply(200, pi);
      }
      setMetadata(pi.metadata, params.metadata);
      return reply(200, pi);
    }
    if (method === "GET" && path === "/refunds") {
      let data = [...refunds.values()].filter((r) => !params.payment_intent || r.payment_intent === params.payment_intent).reverse();
      if (params.starting_after) {
        const at = data.findIndex((r) => r.id === params.starting_after);
        data = data.slice(at + 1);
      }
      const limit = Number(params.limit || 10);
      return reply(200, { object: "list", data: data.slice(0, limit), has_more: data.length > limit });
    }
    if (method === "POST" && path === "/refunds") {
      const pi = intents.get(params.payment_intent);
      if (!pi) return remember(error(404, "resource_missing", "No such payment_intent"));
      if (pi.status !== "succeeded") return remember(error(400, "charge_not_refundable", "Not paid"));
      if (hooks.failRefunds) return error(400, "charge_disputed", "This charge is disputed.");
      const already = [...refunds.values()]
        .filter((r) => r.payment_intent === pi.id && r.status !== "failed" && r.status !== "canceled")
        .reduce((s, r) => s + r.amount, 0);
      const amount = Number(params.amount ?? pi.amount - already);
      if (amount + already > pi.amount) return remember(error(400, "charge_already_refunded", "Refund exceeds amount"));
      const refund = { id: nextId("re"), object: "refund", amount, payment_intent: pi.id, status: "succeeded", reason: params.reason ?? null, metadata: {}, created: now() };
      setMetadata(refund.metadata, params.metadata);
      refunds.set(refund.id, refund);
      return remember(reply(200, refund));
    }
    return error(404, "unknown", `偽の Stripe にない API: ${method} ${path}`);
  }

  return {
    fetch: fetchImpl,
    calls,
    intents,
    refunds,
    customers,
    hooks,
    /** アプリの Stripe の画面で払ったことにする */
    pay(piId, { requiresAuth = false, declines = false, detached = false } = {}) {
      const pi = intents.get(piId);
      const pm = { id: nextId("pm"), requiresAuth, declines, detached };
      paymentMethods.set(pm.id, pm);
      pi.status = "succeeded";
      pi.payment_method = pm.id;
      return pm;
    },
    /** 返金を1件、そのまま置く(失敗した返金など) */
    addRefund(piId, { day, amount, status }) {
      const refund = { id: nextId("re"), object: "refund", amount, payment_intent: piId, status, reason: null,
                       metadata: { app: "goukakulock", day, outcome: "achieved" }, created: now() };
      refunds.set(refund.id, refund);
      return refund;
    },
    paymentMethod(id) {
      return paymentMethods.get(id);
    },
  };
}
