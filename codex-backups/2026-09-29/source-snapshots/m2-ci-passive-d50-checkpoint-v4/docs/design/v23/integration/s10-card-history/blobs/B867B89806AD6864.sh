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

# H411 shared execution admission. Original absent/none routes retain their commands.
shared_build_mode="${CI_S10_4_SHARED_BUILD_MODE:-none}"
case "$shared_build_mode" in
  none)
    test -z "${CI_S10_4_SHARED_XCTESTRUN_PATH:-}"
    test -z "${CI_S10_4_SHARED_PRODUCTS_ROOT:-}"
    test -z "${CI_S10_4_SHARED_PAYLOAD_RUN_ID:-}"
    case "${CI_S10_4_SHARED_EXECUTION_LANE:-none}" in none | "") ;; *) exit 65 ;; esac
    test "${WORKER_S10_4_MINIMUM_SEGMENT_ID:-none}" = none
    for minimum_key in CI_S10_4_MINIMUM_SEGMENT_ID CI_S10_4_MINIMUM_SEGMENT_HEAD \
      CI_S10_4_MINIMUM_SEGMENT_REF CI_S10_4_MINIMUM_SEGMENT_EXECUTION_LANE; do
      if env | LC_ALL=C grep -Eq "^(TEST_RUNNER_)?${minimum_key}="; then
        printf 'minimum segment binding supplied outside shared consumer mode\n' >&2
        exit 65
      fi
    done
    ;;
  producer | consumer)
    python3 - producer <<'H411_SHARED_ADMISSION'
import json
import os
from pathlib import Path
import re
import sys


def require(value, message):
    if not value:
        raise SystemExit("invalid H411 shared execution: " + message)


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)


def validate_shared(environment, script_role):
    e = environment
    mode = e.get("CI_S10_4_SHARED_BUILD_MODE")
    require(mode == script_role and mode in ("producer", "consumer"), "script/mode mismatch")
    require(e.get("GITHUB_REPOSITORY") == "Asset-Rounds/AssetRounds", "repository")
    require(e.get("GITHUB_REF") == "refs/heads/phase/s10-brand-refresh", "ref")
    require(re.fullmatch(r"[0-9a-f]{40}", e.get("GITHUB_SHA", "")), "head")
    require(e.get("CI_TASK_ID") == "S10.4" and e.get("CI_TIER") == "F25", "task/tier")
    require(e.get("PROJECT_PATH") == "FieldEvidenceApp.xcodeproj"
            and e.get("SCHEME") == "FieldEvidenceApp" and e.get("CONFIGURATION") == "Debug", "project/scheme/configuration")
    require(e.get("CODE_SIGNING_ALLOWED") == "NO", "unsigned execution")
    require(e.get("EXPECTED_XCODE_VERSION") == "Xcode 26.6"
            and e.get("EXPECTED_XCODE_BUILD") == "Build version 17F113", "pinned toolchain")
    require(e.get("CI_S10_4_PILOT_MODE") == "false"
            and e.get("CI_S10_4_UNIT_ONLY") == "false"
            and e.get("CI_S10_4_PAYLOAD_ARTIFACT_NAME", "") == "", "old pilot/unit-only/payload mode")
    require(not any(value for key, value in e.items()
                    if key.startswith("CI_S10_4_PILOT_") and key not in (
                        "CI_S10_4_PILOT_MODE", "CI_S10_4_PILOT_CREATED_SIMULATOR_UDID")), "old pilot provenance")
    # The existing workflow stores its newly created shared Simulator in this legacy-named slot.
    # It is isolation identity only, never a pilot payload or qualification admission.
    require(e.get("CI_S10_4_PILOT_CREATED_SIMULATOR_UDID") == e.get("CI_SIMULATOR_UDID")
            and e.get("CI_SIMULATOR_INITIAL_STATE") == "Shutdown", "fresh owned shared Simulator")
    for key in ("CI_S10_4_DIAGNOSTIC_PROBE_ID", "CI_S10_4_DIAGNOSTIC_EXECUTION_LANE",
                "WORKER_S10_4_DIAGNOSTIC_PROBE_ID", "WORKER_S10_4_DIAGNOSTIC_EXECUTION_LANE"):
        require(e.get(key, "none") == "none", "diagnostic admission")
    require(not e.get("CI_S10_4_DIAGNOSTIC_PROBE_TIMEOUT_SECONDS", ""), "diagnostic timeout")
    for key in e:
        require(not key.startswith(("TEST_RUNNER_CI_S10_4_SHARED_", "TEST_RUNNER_CI_S10_4_PILOT_",
                                   "TEST_RUNNER_CI_S10_4_DIAGNOSTIC_")), "foreign test-runner mode key")
        require(key not in ("TEST_RUNNER_CI_S10_4_EXECUTION_ROLE", "TEST_RUNNER_CI_S10_4_EXECUTION_LANE"), "foreign test-runner role/lane")
    if mode == "producer":
        require(bool(e.get("BITRISE_BUILD_CACHE_AUTH_TOKEN", ""))
                and e.get("BITRISE_BUILD_CACHE_WORKSPACE_ID") == "b8052f5a8394f80a"
                and e.get("BITRISE_BUILD_CACHE_BENCHMARK_PHASE_XCODE") == "established", "producer cache wrapper binding")
    else:
        require(not e.get("BITRISE_BUILD_CACHE_AUTH_TOKEN", "")
                and not e.get("BITRISE_BUILD_CACHE_WORKSPACE_ID", ""), "consumer cache credentials")

    workspace = Path(e.get("GITHUB_WORKSPACE", ""))
    require(workspace.is_absolute() and workspace.is_dir() and workspace.resolve() == workspace
            and not workspace.is_symlink(), "physical checkout")
    contract = read_json(workspace / "Scripts/s10-4-shards.json")
    require(contract.get("schemaVersion") == 1 and contract.get("taskID") == "S10.4", "shard contract")
    shards = contract.get("shards")
    require(isinstance(shards, list) and len(shards) == 14
            and len({row["shardID"] for row in shards}) == 14, "fourteen unique shards")
    selected = [row for row in shards if row["shardID"] == e.get("CI_S10_4_SHARD_ID")]
    require(len(selected) == 1, "frozen shard")
    shard = selected[0]
    require(isinstance(shard.get("accessibilityFeatures"), list) and len(shard["accessibilityFeatures"]) == 1, "single profile accessibility feature")
    profiles = [row for row in contract["deviceProfiles"] if row["deviceProfileID"] == shard["deviceProfileID"]]
    require(len(profiles) == 1, "frozen device profile")
    profile = profiles[0]
    expected = {
        "CI_S10_4_SHARD_ID": shard["shardID"],
        "CI_S10_4_SHARD_ORDINAL": str(shard["ordinal"]),
        "CI_S10_4_REQUIREMENT_ID": shard["requirementID"],
        "CI_S10_4_DEVICE_PROFILE_ID": shard["deviceProfileID"],
        "CI_S10_4_ACCESSIBILITY_FEATURE": shard["accessibilityFeatures"][0],
        "CI_S10_4_ACCESSIBILITY_FEATURES": ",".join(shard["accessibilityFeatures"]),
        "CI_S10_4_PROVISION_RUNTIME": str(profile["provisionRuntime"]).lower(),
        "CI_S10_4_RUNTIME_DOWNLOAD_VERSION": profile["runtimeDownloadVersion"],
        "SIMULATOR_RUNTIME": profile["simulatorRuntime"],
        "SIMULATOR_RUNTIME_BUILD": profile["simulatorRuntimeBuild"],
        "SIMULATOR_NAME": profile["simulatorName"],
    }
    environment_fields = {
        "APPEARANCE": "appearance", "CONTRAST": "contrast", "CONTENT_SIZE_CATEGORY": "contentSizeCategory",
        "LOCALE": "locale", "LAYOUT_DIRECTION": "layoutDirection", "DIFFERENTIATE_WITHOUT_COLOR": "differentiateWithoutColor",
        "REDUCE_MOTION": "reduceMotion", "REDUCE_TRANSPARENCY": "reduceTransparency",
    }
    for suffix, field in environment_fields.items():
        value = shard["environment"][field]
        expected["CI_S10_4_" + suffix] = str(value).lower() if isinstance(value, bool) else value
    require(all(e.get(key) == value for key, value in expected.items()), "profile/runtime tuple")
    require(re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", e.get("CI_SIMULATOR_UDID", "")), "Simulator UDID")
    require(e.get("CI_DESTINATION") == "platform=iOS Simulator,id=" + e["CI_SIMULATOR_UDID"], "destination")
    selection = read_json(workspace / "Scripts/ci-selection.json")
    expected_selection = {
        "schemaVersion": 1, "taskID": "S10.4", "tier": "F25", "runUISmoke": True,
        "setupArtifactTimeoutSeconds": 420, "buildTimeoutSeconds": 900, "testTimeoutSeconds": 1200,
        "uiTimeoutSeconds": 2520, "totalBudgetSeconds": 4500,
        "unitTestSelectors": ["FieldEvidenceAppTests/S10_4AutomatedBrandLabTests"],
        "uiTestSelectors": ["FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests"],
    }
    require(json.dumps(selection, sort_keys=True, allow_nan=False)
            == json.dumps(expected_selection, sort_keys=True), "canonical selector/watchdogs")

    minimum_keys = ["CI_S10_4_MINIMUM_SEGMENT_ID", "CI_S10_4_MINIMUM_SEGMENT_HEAD",
                    "CI_S10_4_MINIMUM_SEGMENT_REF", "CI_S10_4_MINIMUM_SEGMENT_EXECUTION_LANE"]
    segment = e.get("CI_S10_4_SEGMENT_ID")
    minimum_segment = e.get("WORKER_S10_4_MINIMUM_SEGMENT_ID", "none")
    if mode == "producer":
        require(e.get("CI_S10_4_SHARED_EXECUTION_LANE") == "s10-4-shared-build-producer", "producer lane")
        require(e.get("CI_RUNNER_PROVIDER") == "bitrise" and e.get("CI_RUNNER_LABEL") == "bitrise-runner-Asset Roundddd", "producer provider")
        require(e.get("CI_RUN_UI_SMOKE") == "false" and e.get("CI_S10_4_EXECUTION_ROLE") == "independent", "producer role")
        require(shard["shardID"] == "s10.4.current.default-light" and segment == "none"
                and minimum_segment == "none" and not e.get("CI_S10_4_SHARED_PAYLOAD_RUN_ID", ""), "producer tuple")
        require(not any(key in e or "TEST_RUNNER_" + key in e for key in minimum_keys), "producer minimum keys")
    else:
        require(e.get("CI_S10_4_SHARED_EXECUTION_LANE") == "github-xcode-26.6-shared-build-acceptance", "consumer lane")
        require(e.get("CI_RUNNER_PROVIDER") == "github" and e.get("CI_RUNNER_LABEL") == "macos-26", "consumer provider")
        require(e.get("CI_RUN_UI_SMOKE") == "true" and e.get("CI_S10_4_EXECUTION_ROLE") == "payload-consumer", "consumer role")
        require(re.fullmatch(r"[1-9][0-9]*", e.get("CI_S10_4_SHARED_PAYLOAD_RUN_ID", "")), "producer run ID")
        require(segment in ("none", "segment-1", "segment-2", "segment-3"), "AX segment")
        require(segment == "none" or shard["shardID"] == "s10.4.current.ax-text", "AX shard/segment")
        require(minimum_segment in ("none", "minimum-segment-1", "minimum-segment-2", "minimum-segment-3"), "minimum segment")
        if minimum_segment == "none":
            require(not any(key in e or "TEST_RUNNER_" + key in e for key in minimum_keys), "minimum keys outside selected segment")
        else:
            require(8 <= shard["ordinal"] <= 14 and segment == "none", "minimum shard/segment")
            minimum_expected = dict(zip(minimum_keys, [minimum_segment, e["GITHUB_SHA"], e["GITHUB_REF"],
                                                      "github-xcode-26.6-shared-build-acceptance"]))
            for key, value in minimum_expected.items():
                require(e.get("TEST_RUNNER_" + key) == value, "minimum launch binding")
                require(key not in e or e[key] == value, "conflicting host minimum binding")
        expected["CI_S10_4_SEGMENT_ID"] = segment
        expected["CI_TASK_ID"] = "S10.4"
        expected["CI_SIMULATOR_UDID"] = e["CI_SIMULATOR_UDID"]
        for key, value in expected.items():
            require(e.get("TEST_RUNNER_" + key) == value, "test-runner profile/runtime binding")
        expected_launch_keys = {"TEST_RUNNER_" + key for key in expected if key.startswith("CI_S10_4_")}
        if minimum_segment != "none":
            expected_launch_keys.update("TEST_RUNNER_" + key for key in minimum_keys)
        require({key for key in e if key.startswith("TEST_RUNNER_CI_S10_4_")} == expected_launch_keys, "closed UI launch keys")

    temporary_root = Path(e.get("RUNNER_TEMP", ""))
    require(temporary_root.is_absolute() and temporary_root.is_dir() and temporary_root.resolve() == temporary_root, "physical runner temporary root")
    root_name = "FieldEvidenceSharedPrepared" if mode == "producer" else "FieldEvidenceSharedRestore"
    products = temporary_root / root_name / "payload/FieldEvidenceDerivedData/Build/Products"
    require(products.is_dir() and not products.is_symlink() and products.resolve() == products, "prepared/restored products root")
    require(e.get("CI_S10_4_SHARED_PRODUCTS_ROOT") == str(products), "workflow products binding")
    xctestrun = Path(e.get("CI_S10_4_SHARED_XCTESTRUN_PATH", ""))
    require(xctestrun.is_absolute() and xctestrun.is_file() and not xctestrun.is_symlink()
            and xctestrun.resolve() == xctestrun and xctestrun.suffix == ".xctestrun"
            and xctestrun.is_relative_to(products), "exact physical xctestrun")
    require(list(products.rglob("*.xctestrun")) == [xctestrun], "single prepared/restored xctestrun")
    artifact_root = Path(e.get("CI_ARTIFACT_DIR", ""))
    require(artifact_root.is_absolute() and artifact_root.is_dir() and artifact_root.resolve() == artifact_root
            and not artifact_root.is_symlink(), "physical evidence directory")
    if mode == "consumer":
        require(not any((artifact_root / name).exists() or (artifact_root / name).is_symlink()
                        for name in ["Build.xcresult", "UnitTests.xcresult", "build-smoke.log", "test-smoke.log"]), "consumer local build/unit evidence")
        derived = temporary_root / "FieldEvidenceDerivedData"
        require(not (derived / "Logs/Build").exists() and not (derived / "Build/Intermediates.noindex").exists(), "consumer rebuild products")


if __name__ == "__main__":
    try:
        validate_shared(os.environ, sys.argv[1])
    except (KeyError, TypeError, ValueError, OSError) as error:
        raise SystemExit("invalid H411 shared execution input: " + type(error).__name__)
H411_SHARED_ADMISSION
    test "$(git rev-parse HEAD)" = "${GITHUB_SHA:?}"
    test "$(pwd -P)" = "${GITHUB_WORKSPACE:?}"
    ;;
  *) printf 'invalid H411 shared build mode\n' >&2; exit 65 ;;
esac
# End H411 shared execution admission.

if [ "$shared_build_mode" = producer ]; then
  shared_unit_command=(
    xcodebuild
    -xctestrun "$CI_S10_4_SHARED_XCTESTRUN_PATH"
    -destination "$CI_DESTINATION"
    -resultBundlePath "$result_bundle_path"
    "${only_testing_args[@]}"
    CODE_SIGNING_ALLOWED=NO
    test-without-building
  )
  python3 - "$CI_ARTIFACT_DIR/s10-4-shared-unit-command.json" "${shared_unit_command[@]}" <<'H411_SHARED_COMMAND'
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
  "${shared_unit_command[@]}"
  test -d "$result_bundle_path"
  test -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)"
  exit 0
fi

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
