#!/bin/bash
# シミュレータでアプリを一度起動して、起動の様子を残す(UI テストの前の「温め」をかねる)。
# 大きなアプリの初回起動は遅く、UI テストの起動待ちが切れることがあるので、先に一度起動しておく。
# 起動が止まっているときに原因がわかるよう、画面・メインスレッドの中身(sample)・ログを残す。
#
# 使い方: scripts/launch-probe.sh <シミュレータの UDID> <GoukakuLock.app> <出力フォルダ>
set -u
UDID="$1"
APP="$2"
OUT="$3"
BUNDLE_ID=com.aokijp.goukakulock
mkdir -p "$OUT"

# 時間を区切って動かす(macOS には timeout がないので perl で)
limit() { local seconds="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"; }

echo "== install"
limit 180 xcrun simctl install "$UDID" "$APP" || echo "install failed ($?)"

echo "== launch"
START=$(date +%s)
limit 120 xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiTesting -uiTestingScriptedAI > "$OUT/launch.txt" 2>&1
echo "launch exit=$? after $(( $(date +%s) - START ))s"
cat "$OUT/launch.txt"
PID=$(sed -nE 's/.*: ([0-9]+)$/\1/p' "$OUT/launch.txt" | tail -n 1)
echo "pid=${PID:-?}"

for WAIT in 10 30; do
  sleep $(( WAIT == 10 ? 10 : 20 ))
  echo "== ${WAIT}s"
  limit 30 xcrun simctl io "$UDID" screenshot "$OUT/screen-${WAIT}s.png" > /dev/null 2>&1 || echo "screenshot failed"
  if [ -n "${PID:-}" ] && kill -0 "$PID" 2> /dev/null; then
    echo "running"
    limit 30 sample "$PID" 2 -file "$OUT/sample-${WAIT}s.txt" > /dev/null 2>&1 || echo "sample failed"
    # メインスレッドの頭のほうだけ出す(全体はファイルに)
    [ -f "$OUT/sample-${WAIT}s.txt" ] && grep -m 1 -A 40 "Thread_.*DispatchQueue_1: com.apple.main-thread" "$OUT/sample-${WAIT}s.txt" | cut -c1-200
  else
    echo "not running (crashed or exited)"
  fi
done

echo "== log"
limit 60 xcrun simctl spawn "$UDID" log show --style compact --last 3m \
  --predicate 'process == "GoukakuLock" AND (messageType == error OR messageType == fault OR subsystem BEGINSWITH "com.aokijp")' \
  > "$OUT/log.txt" 2>&1 || true
tail -n 40 "$OUT/log.txt"
# クラッシュの記録(あれば)
ls -t ~/Library/Logs/DiagnosticReports 2> /dev/null | grep -i goukaku | head -n 3 | while read -r f; do
  cp "$HOME/Library/Logs/DiagnosticReports/$f" "$OUT/" && echo "crash report: $f" && head -n 60 "$HOME/Library/Logs/DiagnosticReports/$f"
done

limit 30 xcrun simctl terminate "$UDID" "$BUNDLE_ID" > /dev/null 2>&1 || true
exit 0
