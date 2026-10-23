#!/bin/zsh
set -eu
cd "${0:A:h}/.."
device_id="${EARSHOT_SIMULATOR_ID:-670AA0BD-A1DF-4768-835F-966A0D09E7B3}"
result_path="${EARSHOT_RESULT_PATH:-TestResults/Earshot-$(date +%Y%m%d-%H%M%S).xcresult}"
mkdir -p TestResults
# Ad hoc signing retains the actual App Group entitlement without a developer
# account. An unsigned build can compile but cannot test shared-container access.
build_arguments=(-project Earshot.xcodeproj -scheme Earshot -configuration Debug
  -destination "platform=iOS Simulator,id=$device_id" -derivedDataPath build
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
xcodebuild "${build_arguments[@]}" build-for-testing
xcrun simctl bootstatus "$device_id" -b
xcrun simctl install "$device_id" build/Build/Products/Debug-iphonesimulator/Earshot.app
# Isolate the real record/play/delete flow from Simulator permission-alert timing.
# This is a Simulator-only test grant, not evidence of first-install/device consent.
xcrun simctl privacy "$device_id" grant microphone dev.earshot.ios
xcodebuild "${build_arguments[@]}" -resultBundlePath "$result_path" test-without-building
