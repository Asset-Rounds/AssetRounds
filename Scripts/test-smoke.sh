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
pilot_execution_role="${CI_S10_4_EXECUTION_ROLE:-}"
pilot_mode="${CI_S10_4_PILOT_MODE:-}"
case "$pilot_execution_role:$pilot_mode" in
  payload-consumer:true) pilot_consumer=true ;;
  : | independent:false) ;;
  *) printf 'incomplete or malformed S10.4 pilot consumer mode\n' >&2; exit 65 ;;
esac

if [ "$pilot_consumer" = false ]; then
  pilot_test_runner_names=(
    TEST_RUNNER_CI_S10_4_EXECUTION_ROLE
    TEST_RUNNER_CI_S10_4_PILOT_MODE
    TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_ROOT
    TEST_RUNNER_CI_S10_4_PILOT_SOURCE_HEAD
    TEST_RUNNER_CI_S10_4_PILOT_EXPECTED_HEAD
    TEST_RUNNER_CI_S10_4_PILOT_UNIT_SOURCE_SHA256
    TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_VERIFIED
  )
  for pilot_test_runner_name in "${pilot_test_runner_names[@]}"; do
    if env | LC_ALL=C grep -Fq "${pilot_test_runner_name}="; then
      printf 'pilot test-runner binding supplied outside S10.4 pilot consumer mode: %s\n' \
        "$pilot_test_runner_name" >&2
      exit 65
    fi
  done
fi

if [ "$pilot_consumer" = true ]; then
  test "${CI_S10_4_PILOT_PAYLOAD_VERIFIED:?}" = "true"
  test "${CI_S10_4_PILOT_CHECKOUT_VERIFIED:?}" = "true"
  test -z "${BITRISE_BUILD_CACHE_AUTH_TOKEN:-}"
  test -z "${BITRISE_BUILD_CACHE_WORKSPACE_ID:-}"

  pilot_checkout_root="${CI_S10_4_PILOT_CHECKOUT_ROOT:?}"
  pilot_source_head="${CI_S10_4_PILOT_SOURCE_HEAD:?}"
  pilot_expected_head="${CI_S10_4_PILOT_EXPECTED_HEAD:?}"
  pilot_unit_source_sha256="${CI_S10_4_PILOT_UNIT_SOURCE_SHA256:?}"
  pilot_payload_verifier="${CI_S10_4_PILOT_PAYLOAD_VERIFIER:?}"
  case "$pilot_checkout_root" in
    /*) ;;
    *) printf 'pilot checkout root must be absolute: %s\n' "$pilot_checkout_root" >&2; exit 65 ;;
  esac
  case "${GITHUB_WORKSPACE:?}" in
    /*) ;;
    *) printf 'GitHub workspace must be absolute: %s\n' "$GITHUB_WORKSPACE" >&2; exit 65 ;;
  esac
  test -d "$pilot_checkout_root"
  test ! -L "$pilot_checkout_root"
  test -d "$GITHUB_WORKSPACE"
  test ! -L "$GITHUB_WORKSPACE"
  pilot_checkout_root_physical="$(cd -P "$pilot_checkout_root" && pwd)"
  github_workspace_physical="$(cd -P "$GITHUB_WORKSPACE" && pwd)"
  test "$pilot_checkout_root" = "$pilot_checkout_root_physical"
  test "$GITHUB_WORKSPACE" = "$github_workspace_physical"
  test "$pilot_checkout_root" = "$GITHUB_WORKSPACE"
  test "$pilot_checkout_root_physical" = "$github_workspace_physical"
  test -f "$pilot_payload_verifier"
  test -x "$pilot_payload_verifier"
  test ! -L "$pilot_payload_verifier"
  pilot_payload_verifier_physical="$(cd -P "$(dirname "$pilot_payload_verifier")" && pwd)/$(basename "$pilot_payload_verifier")"
  test "$pilot_payload_verifier" = "$pilot_payload_verifier_physical"
  [[ "$pilot_source_head" =~ ^[0-9a-f]{40}$ ]]
  [[ "$pilot_expected_head" =~ ^[0-9a-f]{40}$ ]]
  [[ "${GITHUB_SHA:?}" =~ ^[0-9a-f]{40}$ ]]
  [[ "$pilot_unit_source_sha256" =~ ^[0-9A-F]{64}$ ]]
  test "$pilot_source_head" = "$GITHUB_SHA"
  test "$pilot_expected_head" = "$GITHUB_SHA"
  pilot_verifier_output="$("$pilot_payload_verifier" verify-checkout "$pilot_checkout_root" "$pilot_source_head" "$pilot_unit_source_sha256")"
  test -z "$pilot_verifier_output"

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

  if [ "${TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_ROOT+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_ROOT" = "$pilot_checkout_root"
  fi
  if [ "${TEST_RUNNER_CI_S10_4_PILOT_SOURCE_HEAD+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_PILOT_SOURCE_HEAD" = "$pilot_source_head"
  fi
  if [ "${TEST_RUNNER_CI_S10_4_PILOT_EXPECTED_HEAD+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_PILOT_EXPECTED_HEAD" = "$pilot_expected_head"
  fi
  if [ "${TEST_RUNNER_CI_S10_4_PILOT_UNIT_SOURCE_SHA256+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_PILOT_UNIT_SOURCE_SHA256" = "$pilot_unit_source_sha256"
  fi
  if [ "${TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_VERIFIED+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_VERIFIED" = "true"
  fi
  if [ "${TEST_RUNNER_CI_S10_4_PILOT_MODE+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_PILOT_MODE" = "$pilot_mode"
  fi
  if [ "${TEST_RUNNER_CI_S10_4_EXECUTION_ROLE+x}" = x ]; then
    test "$TEST_RUNNER_CI_S10_4_EXECUTION_ROLE" = "$pilot_execution_role"
  fi
  export TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_ROOT="$pilot_checkout_root"
  export TEST_RUNNER_CI_S10_4_PILOT_SOURCE_HEAD="$pilot_source_head"
  export TEST_RUNNER_CI_S10_4_PILOT_EXPECTED_HEAD="$pilot_expected_head"
  export TEST_RUNNER_CI_S10_4_PILOT_UNIT_SOURCE_SHA256="$pilot_unit_source_sha256"
  export TEST_RUNNER_CI_S10_4_PILOT_CHECKOUT_VERIFIED=true
  export TEST_RUNNER_CI_S10_4_PILOT_MODE="$pilot_mode"
  export TEST_RUNNER_CI_S10_4_EXECUTION_ROLE="$pilot_execution_role"

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
