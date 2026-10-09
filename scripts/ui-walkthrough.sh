#!/bin/bash
# シミュレータ(iPhone 17)で画面を一通り動かして、スクリーンショットを残す(UI テスト)。
# 相棒AIは「見本のAI」で動く(シミュレータでは MLX が動かないため)。
# 結果は build/ に置く:uitest-build.log・uitest.log・UITests.xcresult・launch-probe/
#
# 使い方(macOS + Xcode。先に xcodegen generate しておく): bash scripts/ui-walkthrough.sh
set -u
cd "$(dirname "$0")/.."
mkdir -p build

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
runtimes = sorted((k for k in data if "iOS" in k), reverse=True)
for rt in runtimes:
    for d in data[rt]:
        if d["name"] == "iPhone 17":
            print(d["udid"]); sys.exit()
')
if [ -z "$UDID" ]; then
  echo "iPhone 17 のシミュレータが見つからない"
  exit 1
fi
echo "simulator: $UDID"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4 || true

# 見やすいログ(なければそのまま)
beautify() { if command -v xcbeautify > /dev/null; then xcbeautify --renderer github-actions; else cat; fi; }

set -o pipefail
xcodebuild build-for-testing \
  -project GoukakuLock.xcodeproj \
  -scheme GoukakuLock \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath build/DerivedData-Sim \
  -skipPackagePluginValidation -skipMacroValidation \
  2>&1 | tee build/uitest-build.log | beautify || exit $?

# 一度起動して温める(初回起動が遅いと UI テストの起動待ちが切れる)。起動の様子も残す
bash scripts/launch-probe.sh "$UDID" build/DerivedData-Sim/Build/Products/Debug-iphonesimulator/GoukakuLock.app build/launch-probe

xcodebuild test-without-building \
  -project GoukakuLock.xcodeproj \
  -scheme GoukakuLock \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath build/DerivedData-Sim \
  -resultBundlePath build/UITests.xcresult \
  -skipPackagePluginValidation -skipMacroValidation \
  2>&1 | tee build/uitest.log | beautify
