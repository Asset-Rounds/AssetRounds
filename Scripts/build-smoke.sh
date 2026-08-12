#!/bin/bash

set -euo pipefail

derived_data_path="${RUNNER_TEMP:?}/FieldEvidenceDerivedData"
result_bundle_path="${CI_ARTIFACT_DIR:?}/Build.xcresult"
expected_destination="platform=iOS Simulator,id=${CI_SIMULATOR_UDID:?}"

test "${CI_DESTINATION:?}" = "$expected_destination"
test "${CODE_SIGNING_ALLOWED:-}" = "NO"
test ! -e "$result_bundle_path"
mkdir -p "$CI_ARTIFACT_DIR" "$derived_data_path"

xcodebuild \
  -project "${PROJECT_PATH:?}" \
  -scheme "${SCHEME:?}" \
  -configuration "${CONFIGURATION:?}" \
  -destination "$CI_DESTINATION" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

test -d "$result_bundle_path"
test -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)"

app_product="$derived_data_path/Build/Products/Debug-iphonesimulator/FieldEvidenceApp.app"
test -d "$app_product"
test -f "$app_product/Info.plist"
test -n "$(find "$derived_data_path/Build/Products" -type f -name '*.xctestrun' -print -quit)"
