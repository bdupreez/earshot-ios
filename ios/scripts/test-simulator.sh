#!/bin/zsh
set -eu
cd "${0:A:h}/.."
device_id="${EARSHOT_SIMULATOR_ID:-670AA0BD-A1DF-4768-835F-966A0D09E7B3}"
result_path="${EARSHOT_RESULT_PATH:-TestResults/Earshot-$(date +%Y%m%d-%H%M%S).xcresult}"
mkdir -p TestResults
xcodebuild -project Earshot.xcodeproj -scheme Earshot -configuration Debug \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build -resultBundlePath "$result_path" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
