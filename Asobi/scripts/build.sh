#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodebuild >/dev/null || { echo 'Xcode 26+ / Swift 6.2+ is required on macOS'; exit 1; }
python3 scripts/verify_models.py
swift test
xcodebuild -resolvePackageDependencies -project Asobi.xcodeproj -scheme Asobi
if [[ "${1:-}" == "signed" ]]; then
  : "${DEVELOPMENT_TEAM:?Set your Apple Developer Team ID}"
  xcodebuild -project Asobi.xcodeproj -scheme Asobi -configuration Release -destination 'generic/platform=iOS' -archivePath build/Asobi.xcarchive DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" -allowProvisioningUpdates archive
  python3 - <<'PY'
import os,plistlib
with open('build/ExportOptions.plist','wb') as f:
 plistlib.dump({'method':os.environ.get('EXPORT_METHOD','debugging'),'teamID':os.environ['DEVELOPMENT_TEAM'],'signingStyle':'automatic','destination':'export'},f)
PY
  xcodebuild -exportArchive -archivePath build/Asobi.xcarchive -exportPath build/export -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates
else
  xcodebuild -project Asobi.xcodeproj -scheme Asobi -configuration Release -destination 'generic/platform=iOS' -archivePath build/Asobi.xcarchive CODE_SIGNING_ALLOWED=NO archive
  echo 'Unsigned archive built. To produce an installable signed IPA, run DEVELOPMENT_TEAM=YOURTEAM bash scripts/build.sh signed'
fi
