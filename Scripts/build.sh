#!/bin/zsh
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
python3 Scripts/generate_project.py
case "${1:-mac}" in
  mac)
    xcodebuild -quiet -project PSDMirror.xcodeproj -scheme PSDMirrorMac -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/Mac build
    ;;
  ios)
    xcodebuild -quiet -project PSDMirror.xcodeproj -scheme PSDMirror -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath build/Device -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
    ;;
  simulator)
    xcodebuild -quiet -project PSDMirror.xcodeproj -scheme PSDMirror -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build/Simulator CODE_SIGNING_ALLOWED=NO build
    ;;
  *) print -u2 'Usage: build.sh mac|ios|simulator'; exit 2 ;;
esac
