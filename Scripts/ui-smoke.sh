#!/bin/bash

set -euo pipefail

derived_data_path="${RUNNER_TEMP:?}/FieldEvidenceDerivedData"
result_bundle_path="${CI_ARTIFACT_DIR:?}/UISmoke.xcresult"
screenshot_path="$CI_ARTIFACT_DIR/ui-final.png"
expected_destination="platform=iOS Simulator,id=${CI_SIMULATOR_UDID:?}"
app_bundle_id="com.palatis3.fieldrecord"

test "${CI_DESTINATION:?}" = "$expected_destination"
test "${CODE_SIGNING_ALLOWED:-}" = "NO"
test ! -e "$result_bundle_path"
test ! -e "$screenshot_path"
mkdir -p "$CI_ARTIFACT_DIR" "$derived_data_path"

only_testing_args=()
while IFS= read -r selector; do
  case "$selector" in
    FieldEvidenceAppUITests/*) ;;
    *) printf 'invalid UI selector: %s\n' "$selector" >&2; exit 65 ;;
  esac
  only_testing_args[${#only_testing_args[@]}]="-only-testing:$selector"
done < <(jq -r '.uiTestSelectors[]' Scripts/ci-selection.json)

test "${#only_testing_args[@]}" -eq 1

xcrun simctl bootstatus "$CI_SIMULATOR_UDID" -b
if xcrun simctl get_app_container "$CI_SIMULATOR_UDID" "$app_bundle_id" app >/dev/null 2>&1; then
  xcrun simctl uninstall "$CI_SIMULATOR_UDID" "$app_bundle_id"
fi

xcodebuild \
  -project "${PROJECT_PATH:?}" \
  -scheme "${SCHEME:?}" \
  -configuration "${CONFIGURATION:?}" \
  -destination "$CI_DESTINATION" \
  -derivedDataPath "$derived_data_path" \
  -resultBundlePath "$result_bundle_path" \
  "${only_testing_args[@]}" \
  CODE_SIGNING_ALLOWED=NO \
  test-without-building

test -d "$result_bundle_path"
test -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)"
xcrun simctl io "$CI_SIMULATOR_UDID" screenshot "$screenshot_path"
test -s "$screenshot_path"
