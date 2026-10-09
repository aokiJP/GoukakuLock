// Stripe の REST API を fetch で呼ぶだけの小さな部品(依存なし。Cloudflare Workers でも Node でも動く)

const API = "https://api.stripe.com/v1";
/** API の版を固定する(アカウントの既定が変わっても、同じ形で返ってくるように) */
export const STRIPE_VERSION = "2024-06-20";

/** Stripe が返したエラー(カードが通らない・確認が要る など) */
export class StripeError extends Error {
  constructor(status, body) {
    const err = (body && body.error) || {};
    super(err.message || `Stripe の呼び出しに失敗しました(${status})`);
    this.name = "StripeError";
    this.status = status;
    this.code = err.code || null;
    this.declineCode = err.decline_code || null;
    this.type = err.type || null;
    this.paymentIntent = err.payment_intent || null;
  }
}

/** { a: 1, metadata: { b: "x" }, list: ["c"] } → a=1&metadata[b]=x&list[0]=c */
export function encodeForm(params, prefix = "", out = []) {
  for (const [key, value] of Object.entries(params ?? {})) {
    if (value === undefined || value === null) continue;
    const name = prefix ? `${prefix}[${key}]` : key;
    if (Array.isArray(value)) {
      value.forEach((item, i) => {
        if (item !== null && typeof item === "object") encodeForm(item, `${name}[${i}]`, out);
        else out.push(`${encodeURIComponent(`${name}[${i}]`)}=${encodeURIComponent(String(item))}`);
      });
    } else if (typeof value === "object") {
      encodeForm(value, name, out);
    } else {
      out.push(`${encodeURIComponent(name)}=${encodeURIComponent(String(value))}`);
    }
  }
  return out.join("&");
}

/**
 * Stripe の呼び出し口
 * @param {string} secretKey sk_test_… か sk_live_…
 * @param {typeof fetch} fetchImpl テストでは偽の Stripe を渡す
 */
export function stripeClient(secretKey, fetchImpl = fetch) {
  if (!secretKey) throw new Error("STRIPE_SECRET_KEY が設定されていません");

  async function call(method, path, params, { idempotencyKey } = {}) {
    let url = API + path;
    const headers = {
      Authorization: `Bearer ${secretKey}`,
      "Stripe-Version": STRIPE_VERSION,
    };
    let body;
    if (method === "GET") {
      const query = encodeForm(params);
      if (query) url += (url.includes("?") ? "&" : "?") + query;
    } else {
      headers["Content-Type"] = "application/x-www-form-urlencoded";
      body = encodeForm(params);
      if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;
    }
    const res = await fetchImpl(url, { method, headers, body });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) throw new StripeError(res.status, json);
    return json;
  }

  const id = (value) => encodeURIComponent(value);
  return {
    createCustomer: (params, opts) => call("POST", "/customers", params, opts),
    createPaymentIntent: (params, opts) => call("POST", "/payment_intents", params, opts),
    retrievePaymentIntent: (piId) => call("GET", `/payment_intents/${id(piId)}`),
    updatePaymentIntent: (piId, params) => call("POST", `/payment_intents/${id(piId)}`, params),
    cancelPaymentIntent: (piId) => call("POST", `/payment_intents/${id(piId)}/cancel`, {}),
    listPaymentIntents: (params) => call("GET", "/payment_intents", params),
    searchPaymentIntents: (params) => call("GET", "/payment_intents/search", params),
    listRefunds: (params) => call("GET", "/refunds", params),
    createRefund: (params, opts) => call("POST", "/refunds", params, opts),
  };
}
