#!/bin/bash

set -euo pipefail

derived_data_path="${RUNNER_TEMP:?}/FieldEvidenceDerivedData"
result_bundle_path="${CI_ARTIFACT_DIR:?}/Build.xcresult"
expected_destination="platform=iOS Simulator,id=${CI_SIMULATOR_UDID:?}"

test "${CI_DESTINATION:?}" = "$expected_destination"
test "${CODE_SIGNING_ALLOWED:-}" = "NO"
test ! -e "$result_bundle_path"
mkdir -p "$CI_ARTIFACT_DIR" "$derived_data_path"

# H411 producer source argv receipt precedes the preserved cache wrapper.
if [ "${CI_S10_4_SHARED_BUILD_MODE:-none}" = producer ]; then
  test "${CI_RUNNER_PROVIDER:-}" = bitrise
  test "${CI_RUNNER_LABEL:-}" = bitrise-m4-pro
  test "${CI_S10_4_SHARED_EXECUTION_LANE:-}" = s10-4-shared-build-producer
  test -n "${BITRISE_BUILD_CACHE_AUTH_TOKEN:-}"
  test "${BITRISE_BUILD_CACHE_WORKSPACE_ID:-}" = c70b2962648b79fb
  test "${BITRISE_BUILD_CACHE_BENCHMARK_PHASE_XCODE:-}" = established
  shared_build_command=(
    xcodebuild
  -project "${PROJECT_PATH:?}"
  -scheme "${SCHEME:?}"
  -configuration "${CONFIGURATION:?}"
  -destination "$CI_DESTINATION"
  -derivedDataPath "$derived_data_path"
  -resultBundlePath "$result_bundle_path"
  CODE_SIGNING_ALLOWED=NO
  build-for-testing
  )
  python3 - "$CI_ARTIFACT_DIR/s10-4-shared-build-command.json" "${shared_build_command[@]}" <<'H411_SHARED_COMMAND'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
arguments = sys.argv[2:]
if not arguments or any(not argument or any(c in argument for c in ("\n", "\r", "\0")) for argument in arguments):
    raise SystemExit("invalid shared command argument vector")
with path.open("x", encoding="utf-8", newline="\n") as stream:
    json.dump(arguments, stream, ensure_ascii=True, separators=(",", ":"))
    stream.write("\n")
H411_SHARED_COMMAND
fi
# End H411 producer source argv receipt.

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
