#!/bin/bash

set -euo pipefail

python3 -B Scripts/v30/validate_v30_provisional_ci_contract.py --hosted --dispatch-ui "${CI_RUN_UI_SMOKE:?}"

derived_data_path="${RUNNER_TEMP:?}/FieldEvidenceDerivedData"
result_bundle_path="${CI_ARTIFACT_DIR:?}/UnitTests.xcresult"
expected_destination="platform=iOS Simulator,id=${CI_SIMULATOR_UDID:?}"

test "${CI_DESTINATION:?}" = "$expected_destination"
test "${CODE_SIGNING_ALLOWED:-}" = "NO"
test ! -e "$result_bundle_path"
mkdir -p "$CI_ARTIFACT_DIR" "$derived_data_path"

only_testing_args=()
while IFS= read -r selector; do
  case "$selector" in
    FieldEvidenceAppTests/*) ;;
    *) printf 'invalid unit selector: %s\n' "$selector" >&2; exit 65 ;;
  esac
  only_testing_args[${#only_testing_args[@]}]="-only-testing:$selector"
done < <(jq -r '.selector.unitTestSelectors[]' docs/design/v30/execution/V30_CI_SELECTION.json)

test "${#only_testing_args[@]}" -gt 0

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
