#!/usr/bin/env bash
# 未署名でビルドした GoukakuLock.app を、エンタイトルメント入りのアドホック署名(証明書なし)にして .ipa に包む。
#   使い方: scripts/package-ipa.sh <GoukakuLock.app のパス> <出力する .ipa のパス>
# アドホック署名は「どのエンタイトルメントが要るか」を中に残すためのもの。実機に入れるときは、
# 有料の Apple Developer Program の証明書とプロビジョニングプロファイルで署名し直す(README 参照)。
set -euo pipefail

APP_IN="$1"
OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/Payload" "$(dirname "$OUT")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
cp -R "$APP_IN" "$WORK/Payload/"
APP="$WORK/Payload/$(basename "$APP_IN")"

sign() {
  local target="$1" entitlements="${2:-}"
  if [[ -n "$entitlements" ]]; then
    codesign --force --sign - --timestamp=none --generate-entitlement-der --entitlements "$entitlements" "$target"
  else
    codesign --force --sign - --timestamp=none "$target"
  fi
}

# 中に入れ子になったフレームワーク(預け金の支払い画面の Stripe など)を先に
if [[ -d "$APP/Frameworks" ]]; then
  find "$APP/Frameworks" -maxdepth 1 \( -name '*.framework' -o -name '*.dylib' \) -print0 | while IFS= read -r -d '' fw; do sign "$fw"; done
fi

sign "$APP/PlugIns/GoukakuMonitor.appex"      "$ROOT/Extensions/Monitor/GoukakuMonitor.entitlements"
sign "$APP/PlugIns/GoukakuShieldConfig.appex" "$ROOT/Extensions/ShieldConfig/GoukakuShieldConfig.entitlements"
sign "$APP/PlugIns/GoukakuShieldAction.appex" "$ROOT/Extensions/ShieldAction/GoukakuShieldAction.entitlements"
sign "$APP/PlugIns/GoukakuWidget.appex"       "$ROOT/Widgets/Extension/GoukakuWidget.entitlements"
sign "$APP"                                   "$ROOT/App/GoukakuLock.entitlements"

codesign --verify --deep --strict --verbose=2 "$APP"
for bundle in "$APP" "$APP"/PlugIns/*.appex; do
  echo "== $(basename "$bundle")"
  codesign -d --entitlements - --xml "$bundle" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null | grep -E '<key>|<string>' || true
done

rm -f "$OUT_ABS"
(cd "$WORK" && zip -qry "$OUT_ABS" Payload)
ls -la "$OUT_ABS"
