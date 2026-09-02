#!/bin/bash

set -euo pipefail

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
done < <(jq -r '.unitTestSelectors[]' Scripts/ci-selection.json)

test "${#only_testing_args[@]}" -gt 0

pilot_consumer=false
if [ "${CI_S10_4_EXECUTION_ROLE:-}" = "payload-consumer" ] && \
   [ "${CI_S10_4_PILOT_MODE:-}" = "true" ]; then
  pilot_consumer=true
fi

if [ "$pilot_consumer" = true ]; then
  test "${CI_S10_4_PILOT_PAYLOAD_VERIFIED:?}" = "true"
  test -z "${BITRISE_BUILD_CACHE_AUTH_TOKEN:-}"
  test -z "${BITRISE_BUILD_CACHE_WORKSPACE_ID:-}"

  pilot_products_root="${RUNNER_TEMP:?}/FieldEvidenceDerivedData/Build/Products"
  pilot_xctestrun_path="${CI_S10_4_PILOT_XCTESTRUN_PATH:?}"
  case "$pilot_products_root" in
    /*) ;;
    *) printf 'pilot products root must be absolute: %s\n' "$pilot_products_root" >&2; exit 65 ;;
  esac
  case "$pilot_xctestrun_path" in
    "$pilot_products_root"/*.xctestrun) ;;
    *) printf 'invalid pilot xctestrun path: %s\n' "$pilot_xctestrun_path" >&2; exit 65 ;;
  esac
  test -d "$pilot_products_root"
  test ! -L "$pilot_products_root"
  test -f "$pilot_xctestrun_path"
  test ! -L "$pilot_xctestrun_path"
  pilot_products_root_physical="$(cd -P "$pilot_products_root" && pwd)"
  pilot_xctestrun_path_physical="$(cd -P "$(dirname "$pilot_xctestrun_path")" && pwd)/$(basename "$pilot_xctestrun_path")"
  test "$pilot_products_root_physical" = "$pilot_products_root"
  test "$pilot_xctestrun_path_physical" = "$pilot_xctestrun_path"
  pilot_xctestrun_paths="$(find "$pilot_products_root" -name '*.xctestrun' -print)"
  test "$(printf '%s\n' "$pilot_xctestrun_paths" | wc -l | tr -d '[:space:]')" = "1"
  test "$pilot_xctestrun_paths" = "$pilot_xctestrun_path"
  test ! -e "$CI_ARTIFACT_DIR/build-smoke.log"
  test ! -e "$derived_data_path/Logs/Build"
  test ! -e "$derived_data_path/Build/Intermediates.noindex"

  xcodebuild \
    -xctestrun "$CI_S10_4_PILOT_XCTESTRUN_PATH" \
    -destination "$CI_DESTINATION" \
    -resultBundlePath "$result_bundle_path" \
    "${only_testing_args[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    test-without-building

  test ! -e "$CI_ARTIFACT_DIR/build-smoke.log"
  test ! -e "$derived_data_path/Logs/Build"
  test ! -e "$derived_data_path/Build/Intermediates.noindex"
else
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
fi

test -d "$result_bundle_path"
test -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)"
