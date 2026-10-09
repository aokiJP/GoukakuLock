// 端末ごとの合い言葉(トークン)。「Stripe の客の id + その署名」なので、サーバーに台帳は要らない。
// 署名の鍵(TOKEN_SECRET)を知らなければ、ほかの人の客の id でトークンを作れない

const encoder = new TextEncoder();

function base64url(bytes) {
  let text = "";
  for (const b of bytes) text += String.fromCharCode(b);
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmac(secret, data) {
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(data)));
}

/** 長さと中身を、かかる時間がそろうように比べる(合い言葉・招待コード) */
export function sameText(a, b) {
  const n = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < n; i++) diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  return diff === 0;
}

export async function makeToken(secret, customerId) {
  if (!secret) throw new Error("TOKEN_SECRET が設定されていません");
  return `${customerId}.${base64url(await hmac(secret, `goukaku-deposit:${customerId}`))}`;
}

/** トークンが正しければ客の id、まちがっていれば null */
export async function readToken(secret, token) {
  if (typeof token !== "string" || !secret) return null;
  const dot = token.lastIndexOf(".");
  if (dot <= 0) return null;
  const customerId = token.slice(0, dot);
  if (!/^cus_[A-Za-z0-9]+$/.test(customerId)) return null;
  const expected = await makeToken(secret, customerId);
  return sameText(expected, token) ? customerId : null;
}
