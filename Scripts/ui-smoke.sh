#!/bin/bash

set -euo pipefail

derived_data_path="${RUNNER_TEMP:?}/FieldEvidenceDerivedData"
result_bundle_path="${CI_ARTIFACT_DIR:?}/UISmoke.xcresult"
screenshot_path="$CI_ARTIFACT_DIR/ui-final.png"
attachment_export_path="${RUNNER_TEMP:?}/FieldEvidenceUISmokeAttachments"
attachment_manifest_path="$attachment_export_path/manifest.json"
failure_attachment_export_path="$CI_ARTIFACT_DIR/ui-failure-attachments"
failure_diagnostic_path="$CI_ARTIFACT_DIR/ui-failure-diagnostics"
expected_destination="platform=iOS Simulator,id=${CI_SIMULATOR_UDID:?}"
app_bundle_id="com.palatis3.fieldrecord"

test "${CI_DESTINATION:?}" = "$expected_destination"
test "${CODE_SIGNING_ALLOWED:-}" = "NO"
test ! -e "$result_bundle_path"
test ! -e "$screenshot_path"
test ! -L "$screenshot_path"
test ! -e "$attachment_export_path"
test ! -L "$attachment_export_path"
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
selected_ui_selector="${only_testing_args[0]#-only-testing:}"
selected_test_class="${selected_ui_selector#FieldEvidenceAppUITests/}"
if ! [[ "$selected_test_class" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || \
   [ "$selected_ui_selector" != "FieldEvidenceAppUITests/$selected_test_class" ]; then
  printf 'UI selector must name exactly one bounded XCUITest class: %s\n' \
    "$selected_ui_selector" >&2
  exit 65
fi

python3 - <<'S10_4_SMOKE_ENV'
import os, runpy
from pathlib import Path
k=runpy.run_path('Scripts/s10-4-build-payload.py')
k['smoke_environment'](os.environ,Path.cwd(),os.environ.get('WORKER_S10_4_MINIMUM_CORE_SMOKE_ID','none'))
S10_4_SMOKE_ENV

diagnostic_probe_id="${CI_S10_4_DIAGNOSTIC_PROBE_ID:-none}"
diagnostic_mode=false
case "$diagnostic_probe_id" in
  none)
    test "${CI_S10_4_DIAGNOSTIC_EXECUTION_LANE:-none}" = "none"
    ;;
  minimum-new-sign | minimum-preflight)
    diagnostic_mode=true
    test "${CI_S10_4_DIAGNOSTIC_EXECUTION_LANE:?}" = \
      "s10-4-focused-diagnostics-development-only"
    test "${CI_S10_4_DIAGNOSTIC_PROBE_TIMEOUT_SECONDS:?}" = "600"
    test "${CI_TASK_ID:?}" = "S10.4"
    test "${CI_TIER:?}" = "F25"
    test "${CI_RUN_UI_SMOKE:?}" = "true"
    test "${CI_RUNNER_PROVIDER:?}" = "github"
    test "${CI_S10_4_EXECUTION_ROLE:?}" = "payload-consumer"
    test "${CI_S10_4_PILOT_MODE:?}" = "true"
    case "$diagnostic_probe_id:${CI_S10_4_SHARD_ID:?}" in
      minimum-new-sign:s10.4.minimum.minimum-os | minimum-preflight:s10.4.minimum.bounded) ;;
      *) exit 1 ;;
    esac
    test "${CI_S10_4_SEGMENT_ID:?}" = "none"
    test "$selected_ui_selector" = \
      "FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests"
    selected_ui_selector="FieldEvidenceAppUITests/S10_4DevelopmentProbeUITests"
    selected_test_class="S10_4DevelopmentProbeUITests"
    only_testing_args=("-only-testing:$selected_ui_selector")
    ;;
  *)
    printf 'invalid S10.4 diagnostic probe ID: %s\n' "$diagnostic_probe_id" >&2
    exit 65
    ;;
esac

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
    python3 - consumer <<'H411_SHARED_ADMISSION'
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
        if e.get("WORKER_S10_4_MINIMUM_CORE_SMOKE_ID", "none") != "none":
            expected_launch_keys.update("TEST_RUNNER_CI_S10_4_MINIMUM_CORE_SMOKE_" + suffix for suffix in ("ID", "HEAD", "REF", "EXECUTION_LANE"))
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

if [ "${CI_RUNNER_PROVIDER:-}" = "github" ] && \
   [ "${CI_TASK_ID:-}" = "S10.4" ] && \
   { [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.current.ax-text" ] || \
     [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.rtl" ]; }; then
  test "${CI_SIMULATOR_BOOT_TIMEOUT_SECONDS:?}" = "900"
  simulator_refresh_log="$CI_ARTIFACT_DIR/ui-simulator-refresh.log"
  test ! -e "$simulator_refresh_log"
  test ! -L "$simulator_refresh_log"
  simulator_refresh_start_epoch="$(date +%s)"
  case "$simulator_refresh_start_epoch" in *[!0-9]* | "") exit 1 ;; esac
  printf 'refresh_start_epoch=%s\nrefresh_udid=%s\nreadiness_budget_seconds=%s\n' \
    "$simulator_refresh_start_epoch" "$CI_SIMULATOR_UDID" \
    "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" \
    | tee "$simulator_refresh_log"
  xcrun simctl shutdown "$CI_SIMULATOR_UDID" 2>&1 \
    | tee -a "$simulator_refresh_log"
  xcrun simctl boot "$CI_SIMULATOR_UDID" 2>&1 \
    | tee -a "$simulator_refresh_log"
  bash Scripts/run-with-timeout.sh "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" \
    xcrun simctl bootstatus "$CI_SIMULATOR_UDID" -b 2>&1 \
    | tee -a "$simulator_refresh_log"
  simulator_refresh_end_epoch="$(date +%s)"
  case "$simulator_refresh_end_epoch" in *[!0-9]* | "") exit 1 ;; esac
  test "$simulator_refresh_end_epoch" -ge "$simulator_refresh_start_epoch"
  simulator_refresh_elapsed_seconds="$(( simulator_refresh_end_epoch - simulator_refresh_start_epoch ))"
  test "$simulator_refresh_elapsed_seconds" -le "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS"
  printf 'refresh_end_epoch=%s\nrefresh_elapsed_seconds=%s\n' \
    "$simulator_refresh_end_epoch" "$simulator_refresh_elapsed_seconds" \
    | tee -a "$simulator_refresh_log"
fi

xcrun simctl bootstatus "$CI_SIMULATOR_UDID" -b
if xcrun simctl get_app_container "$CI_SIMULATOR_UDID" "$app_bundle_id" app >/dev/null 2>&1; then
  xcrun simctl uninstall "$CI_SIMULATOR_UDID" "$app_bundle_id"
fi

set +e
pilot_consumer=false
if [ "${CI_S10_4_EXECUTION_ROLE:-}" = "payload-consumer" ] && \
   [ "${CI_S10_4_PILOT_MODE:-}" = "true" ]; then
  pilot_consumer=true
fi

# H412 finite shared middle-segment diagnostic admission; no native query or action.
h412_shared_incident_profile=none
if [ "${CI_RUNNER_PROVIDER:-}" = github ] &&
   [ "${CI_TASK_ID:-}" = S10.4 ] &&
   [ "${CI_S10_4_PILOT_MODE:-}" = false ] &&
   [ "${diagnostic_probe_id:-}" = none ] &&
   [ "${CI_S10_4_SEGMENT_ID:-}" = none ] &&
   [ "${CI_S10_4_EXECUTION_ROLE:-}" = payload-consumer ] &&
   [ "${CI_S10_4_SHARED_BUILD_MODE:-}" = consumer ] &&
   [ "${CI_S10_4_SHARED_EXECUTION_LANE:-}" = github-xcode-26.6-shared-build-acceptance ] &&
   [ "${CI_S10_4_DEVICE_PROFILE_ID:-}" = iphone-se-3-ios-18.0-minimum ] &&
   [ "${WORKER_S10_4_MINIMUM_SEGMENT_ID:-}" = minimum-segment-2 ] &&
   [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_ID:-}" = minimum-segment-2 ] &&
   [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_EXECUTION_LANE:-}" = github-xcode-26.6-shared-build-acceptance ] &&
   [ -n "${GITHUB_SHA:-}" ] && [ -n "${GITHUB_REF:-}" ] &&
   [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_HEAD:-}" = "$GITHUB_SHA" ] &&
   [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_REF:-}" = "$GITHUB_REF" ]; then
  case "${CI_S10_4_SHARD_ID:-}:${CI_S10_4_SHARD_ORDINAL:-}:${CI_S10_4_REQUIREMENT_ID:-}" in
    s10.4.minimum.bounded:14:bounded) h412_shared_incident_profile=bounded ;;
    s10.4.minimum.rtl-string:11:rtl_string) h412_shared_incident_profile=rtl-string ;;
    s10.4.minimum.double-length:9:double_length) h412_shared_incident_profile=double-length ;;
  esac
fi
# End H412 finite shared middle-segment diagnostic admission.

ips_test_started_epoch=""
if [ "${CI_RUNNER_PROVIDER:-}" = github ] && [ "${CI_TASK_ID:-}" = S10.4 ]; then
  case "${CI_S10_4_SHARD_ID:-}" in
    s10.4.minimum.minimum-os|s10.4.minimum.accented|s10.4.minimum.bounded|s10.4.minimum.tall|s10.4.minimum.rtl)
      ips_test_started_epoch="$(date +%s)" ;;
    s10.4.minimum.rtl-string)
      if [ "${CI_S10_4_PILOT_MODE:-}" = false ] &&
         [ "$diagnostic_probe_id" = none ] &&
         [ "${CI_S10_4_SEGMENT_ID:-}" = none ] &&
         [ "${CI_S10_4_EXECUTION_ROLE:-}" = independent ]; then
        ips_test_started_epoch="$(date +%s)"
      elif [ "$h412_shared_incident_profile" = rtl-string ]; then
        ips_test_started_epoch="$(date +%s)"
      fi ;;
  esac
fi

if [ "$shared_build_mode" = consumer ]; then
  set -e
  shared_ui_command=(
    xcodebuild
    -xctestrun "$CI_S10_4_SHARED_XCTESTRUN_PATH"
    -destination "$CI_DESTINATION"
    -resultBundlePath "$result_bundle_path"
    "${only_testing_args[@]}"
    CODE_SIGNING_ALLOWED=NO
    test-without-building
  )
  python3 - "$CI_ARTIFACT_DIR/s10-4-shared-ui-command.json" "${shared_ui_command[@]}" <<'H411_SHARED_COMMAND'
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
  set +e
  "${shared_ui_command[@]}"
elif [ "$pilot_consumer" = true ]; then
  set -e
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

  set +e
  xcodebuild \
    -xctestrun "$CI_S10_4_PILOT_XCTESTRUN_PATH" \
    -destination "$CI_DESTINATION" \
    -resultBundlePath "$result_bundle_path" \
    "${only_testing_args[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    test-without-building
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
xcodebuild_status=$?
set -e

if [ "$pilot_consumer" = true ]; then
  test ! -e "$CI_ARTIFACT_DIR/build-smoke.log"
  test ! -e "$derived_data_path/Logs/Build"
  test ! -e "$derived_data_path/Build/Intermediates.noindex"
fi

if [ "$diagnostic_mode" = true ]; then
  printf 'S10_4_DIAGNOSTIC_WORKER probeID=%s executionLane=%s timeoutSeconds=%s selectedSelector=%s\n' \
    "$diagnostic_probe_id" "$CI_S10_4_DIAGNOSTIC_EXECUTION_LANE" \
    "$CI_S10_4_DIAGNOSTIC_PROBE_TIMEOUT_SECONDS" "$selected_ui_selector"
fi

if [ "$xcodebuild_status" -ne 0 ]; then
  if [ -d "$result_bundle_path" ] && \
     [ -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)" ]; then
    test ! -e "$failure_attachment_export_path"
    test ! -L "$failure_attachment_export_path"
    mkdir -p "$failure_attachment_export_path"
    if ! xcrun xcresulttool export attachments \
      --path "$result_bundle_path" \
      --output-path "$failure_attachment_export_path"; then
      printf 'failed to export non-accepting UI failure attachments\n' >&2
    fi
  fi

  set +e
  if [ -e "$failure_diagnostic_path" ] || \
     [ -L "$failure_diagnostic_path" ]; then
    printf 'refusing existing UI failure diagnostic path: %s\n' \
      "$failure_diagnostic_path" >&2
    exit "$xcodebuild_status"
  fi
  if ! mkdir -p "$failure_diagnostic_path"; then
    printf 'failed to create UI failure diagnostic path: %s\n' \
      "$failure_diagnostic_path" >&2
    exit "$xcodebuild_status"
  fi
  diagnostic_status_path="$failure_diagnostic_path/status.txt"
  diagnostic_context_path="$failure_diagnostic_path/context.txt"
  {
    printf 'diagnostic_started_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'xcodebuild_status=%s\n' "$xcodebuild_status"
    printf 'github_run_id=%s\n' "${GITHUB_RUN_ID:-}"
    printf 'github_run_attempt=%s\n' "${GITHUB_RUN_ATTEMPT:-}"
    printf 'github_sha=%s\n' "${GITHUB_SHA:-}"
    printf 'github_ref=%s\n' "${GITHUB_REF:-}"
    printf 'runner_name=%s\n' "${RUNNER_NAME:-}"
    printf 'runner_os=%s\n' "${RUNNER_OS:-}"
    printf 'runner_arch=%s\n' "${RUNNER_ARCH:-}"
    printf 'simulator_udid=%s\n' "$CI_SIMULATOR_UDID"
    printf 'destination=%s\n' "$CI_DESTINATION"
    printf 'selected_ui_selector=%s\n' "$selected_ui_selector"
  } > "$diagnostic_context_path"
  : > "$diagnostic_status_path"

  run_diagnostic() {
    diagnostic_name="$1"
    shift
    "$@"
    diagnostic_status="$?"
    printf '%s=%s\n' "$diagnostic_name" "$diagnostic_status" \
      >> "$diagnostic_status_path"
    return 0
  }


  # K404 failure-only bounded/accented/RTL app lifecycle context.
  diagnostic_report_app_patterns=()
  if [ "${CI_RUNNER_PROVIDER:-}" = "github" ] && \
     [ "${CI_TASK_ID:-}" = "S10.4" ] && \
     { [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.bounded" ] || \
       [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.accented" ] || \
       [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.rtl" ] || \
       { [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.rtl-string ] && \
         [ "${CI_S10_4_PILOT_MODE:-}" = false ] && \
         [ "$diagnostic_probe_id" = none ] && \
         [ "${CI_S10_4_SEGMENT_ID:-}" = none ] && \
         [ "${CI_S10_4_EXECUTION_ROLE:-}" = independent ]; } || [ "$h412_shared_incident_profile" = rtl-string ]; }; then
    diagnostic_report_app_patterns=(-o -iname 'FieldEvidenceApp*')
    simulator_lifecycle_raw="$(mktemp "${RUNNER_TEMP:?}/FieldEvidenceSimulatorLifecycle.XXXXXX")"
    simulator_lifecycle_temp_status="$?"
    printf 'simulator_lifecycle_temp=%s\n' "$simulator_lifecycle_temp_status" \
      >> "$diagnostic_status_path"
    if [ "$simulator_lifecycle_temp_status" -eq 0 ]; then
      run_diagnostic simulator_lifecycle_log \
        Scripts/run-with-timeout.sh 30 \
        xcrun simctl spawn "$CI_SIMULATOR_UDID" log show \
          --last 10m \
          --style compact \
          --predicate \
            '(process == "FieldEvidenceApp") OR (process == "testmanagerd") OR (((process == "runningboardd") OR (process == "SpringBoard")) AND ((eventMessage CONTAINS "FieldEvidenceApp") OR (eventMessage CONTAINS "com.palatis3.fieldrecord")))' \
        > "$simulator_lifecycle_raw" 2>&1
      simulator_lifecycle_incomplete=false
      if [ "$diagnostic_status" -ne 0 ]; then
        simulator_lifecycle_incomplete=true
      fi
      simulator_lifecycle_bytes_at_snapshot="$(
        LC_ALL=C wc -c < "$simulator_lifecycle_raw" | tr -d '[:space:]'
      )"
      # Read no more than the measured snapshot even if a timed-out child survives.
      /usr/bin/head -c "$simulator_lifecycle_bytes_at_snapshot" "$simulator_lifecycle_raw" \
        | /usr/bin/tail -c 1048576 \
        > "$failure_diagnostic_path/simulator-app-lifecycle.log"
      simulator_lifecycle_snapshot_status="$?"
      if [ "$simulator_lifecycle_snapshot_status" -ne 0 ]; then
        simulator_lifecycle_incomplete=true
      fi
      simulator_lifecycle_retained_bytes="$(
        LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-app-lifecycle.log" \
          | tr -d '[:space:]'
      )"
      simulator_lifecycle_truncated=false
      if [ "$simulator_lifecycle_bytes_at_snapshot" -gt 1048576 ]; then
        simulator_lifecycle_truncated=true
      fi
      printf 'simulator_lifecycle_snapshot=%s\nsimulator_lifecycle_bytes_at_snapshot=%s\nsimulator_lifecycle_retained_bytes=%s\nsimulator_lifecycle_truncated=%s\nsimulator_lifecycle_incomplete=%s\nsimulator_lifecycle_capture=bounded_snapshot_not_completion_proof\n' \
        "$simulator_lifecycle_snapshot_status" "$simulator_lifecycle_bytes_at_snapshot" \
        "$simulator_lifecycle_retained_bytes" "$simulator_lifecycle_truncated" \
        "$simulator_lifecycle_incomplete" >> "$diagnostic_status_path"
      rm -f "$simulator_lifecycle_raw"
    fi
  fi
  # End K404 failure-only app lifecycle context.

  # K428 supplies the app incident input required by H408 for ordinary minimum-OS and tall failures.
  if [ "${CI_RUNNER_PROVIDER:-}" = "github" ] && \
     [ "${CI_TASK_ID:-}" = "S10.4" ] && \
     [ "${CI_S10_4_PILOT_MODE:-false}" = "false" ] && \
     { [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.minimum-os" ] || \
       [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.tall" ]; }; then
    diagnostic_report_app_patterns=(-o -iname 'FieldEvidenceApp*')
  fi

  if [ -d "$result_bundle_path" ] && \
     [ -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)" ]; then
    run_diagnostic xcresult_test_results \
      Scripts/run-with-timeout.sh 30 \
      xcrun xcresulttool get test-results tests \
        --path "$result_bundle_path" \
        --compact \
      > "$failure_diagnostic_path/xcresult-test-results.json" \
      2> "$failure_diagnostic_path/xcresult-test-results.stderr.txt"
  else
    printf 'xcresult_test_results=66\n' >> "$diagnostic_status_path"
  fi

  LC_ALL=C /bin/ps -axo pid,ppid,etime,state,command \
    | /usr/bin/grep -E \
      'testmanagerd|xctest|xcodebuild|CoreSimulatorService|simctl' \
    | /usr/bin/grep -v '[g]rep' \
    > "$failure_diagnostic_path/processes.txt" 2>&1
  printf 'process_snapshot=%s\n' "$?" >> "$diagnostic_status_path"

  host_unified_log_raw="${RUNNER_TEMP:?}/FieldEvidenceHostUnified.log"
  rm -f "$host_unified_log_raw"
  run_diagnostic host_unified_log \
    Scripts/run-with-timeout.sh 45 \
    /usr/bin/log show \
      --last 30m \
      --style compact \
      --predicate \
        '(process == "testmanagerd") OR (process == "xctest") OR (process == "xcodebuild") OR (process == "CoreSimulatorService")' \
    > "$host_unified_log_raw" 2>&1
  host_unified_log_original_bytes=0
  host_unified_log_retained_bytes=0
  if [ -f "$host_unified_log_raw" ]; then
    host_unified_log_original_bytes="$(
      LC_ALL=C wc -c < "$host_unified_log_raw" | tr -d '[:space:]'
    )"
    /usr/bin/head -c 2097152 "$host_unified_log_raw" \
      > "$failure_diagnostic_path/host-unified.log"
    h412_host_prefix_status="$?"
    printf 'host_unified_log_bound=%s\n' "$h412_host_prefix_status" >> "$diagnostic_status_path"
    host_unified_log_retained_bytes="$(
      LC_ALL=C wc -c < "$failure_diagnostic_path/host-unified.log" \
        | tr -d '[:space:]'
    )"
  fi
  printf 'host_unified_log_original_bytes=%s\n' \
    "$host_unified_log_original_bytes" >> "$diagnostic_status_path"
  printf 'host_unified_log_retained_bytes=%s\n' \
    "$host_unified_log_retained_bytes" >> "$diagnostic_status_path"
  # H412 same-query RTL host tail; the original two-MiB prefix is preserved.
  if [ "$h412_shared_incident_profile" = rtl-string ] && [ -f "$host_unified_log_raw" ]; then
    /usr/bin/head -c "$host_unified_log_original_bytes" "$host_unified_log_raw" | /usr/bin/tail -c 1048576 \
      > "$failure_diagnostic_path/host-unified-tail.log"
    h412_host_tail_status="$?"
    h412_host_tail_bytes="$(LC_ALL=C wc -c < "$failure_diagnostic_path/host-unified-tail.log" | tr -d '[:space:]')"
    h412_host_tail_start=0
    if [ "$host_unified_log_original_bytes" -gt 1048576 ]; then
      h412_host_tail_start="$(( host_unified_log_original_bytes - 1048576 ))"
    fi
    h412_host_overlap=0
    if [ "$host_unified_log_retained_bytes" -gt "$h412_host_tail_start" ]; then
      h412_host_overlap="$(( host_unified_log_retained_bytes - h412_host_tail_start ))"
    fi
    h412_host_gap=false
    if [ "$host_unified_log_retained_bytes" -lt "$h412_host_tail_start" ]; then h412_host_gap=true; fi
    h412_host_tail_expected="$(( host_unified_log_original_bytes - h412_host_tail_start ))"
    h412_host_prefix_expected="$host_unified_log_original_bytes"
    if [ "$h412_host_prefix_expected" -gt 2097152 ]; then h412_host_prefix_expected=2097152; fi
    h412_host_prefix_truncated=false
    if [ "$host_unified_log_original_bytes" -gt 2097152 ]; then h412_host_prefix_truncated=true; fi
    h412_host_tail_truncated=false
    if [ "$host_unified_log_original_bytes" -gt 1048576 ]; then h412_host_tail_truncated=true; fi
    h412_host_incomplete=false
    if [ "$diagnostic_status" -ne 0 ] || [ "$h412_host_tail_status" -ne 0 ] || [ "$h412_host_prefix_status" -ne 0 ] ||
       [ "$host_unified_log_retained_bytes" -ne "$h412_host_prefix_expected" ] ||
       [ "$h412_host_tail_bytes" -ne "$h412_host_tail_expected" ] || [ "$h412_host_tail_bytes" -eq 0 ]; then
      h412_host_incomplete=true
    fi
    printf 'host_prefix_truncated=%s\nhost_tail_truncated=%s\nhost_prefix_snapshot_status=%s\n' \
      "$h412_host_prefix_truncated" "$h412_host_tail_truncated" "$h412_host_prefix_status" >> "$diagnostic_status_path"
    printf 'host_tail_query_status=%s\nhost_tail_snapshot_status=%s\nhost_tail_original_bytes=%s\nhost_tail_retained_bytes=%s\nhost_prefix_start_byte=0\nhost_prefix_end_byte=%s\nhost_tail_start_byte=%s\nhost_tail_end_byte=%s\nhost_prefix_tail_overlap_bytes=%s\nhost_prefix_tail_gap=%s\nhost_tail_incomplete=%s\nhost_tail_capture=bounded_same_query_snapshot_not_completion_proof\nhost_tail_acceptance_eligible=false\n' \
      "$diagnostic_status" "$h412_host_tail_status" "$host_unified_log_original_bytes" "$h412_host_tail_bytes" \
      "$host_unified_log_retained_bytes" "$h412_host_tail_start" "$host_unified_log_original_bytes" \
      "$h412_host_overlap" "$h412_host_gap" "$h412_host_incomplete" >> "$diagnostic_status_path"
  fi
  # End H412 same-query RTL host tail.
  rm -f "$host_unified_log_raw"

  # K365 failure-only minimum-OS Simulator accessibility context.
  if [ "${CI_RUNNER_PROVIDER:-}" = "github" ] && \
     [ "${CI_TASK_ID:-}" = "S10.4" ] && \
     [ "${CI_S10_4_SHARD_ID:-}" = "s10.4.minimum.minimum-os" ]; then
    simulator_ax_log_raw="$(mktemp "${RUNNER_TEMP:?}/FieldEvidenceSimulatorAX.XXXXXX")"
    simulator_ax_log_temp_status="$?"
    printf 'simulator_ax_log_temp=%s\n' "$simulator_ax_log_temp_status" \
      >> "$diagnostic_status_path"
    if [ "$simulator_ax_log_temp_status" -eq 0 ]; then
      run_diagnostic simulator_ax_unified_log \
        Scripts/run-with-timeout.sh 30 \
        xcrun simctl spawn "$CI_SIMULATOR_UDID" log show \
          --last 10m \
          --style compact \
          --predicate \
            '(process == "accessibilityd") OR (process == "SpringBoard") OR (process == "keyboardd") OR (subsystem CONTAINS[c] "accessibility")' \
        > "$simulator_ax_log_raw" 2>&1
      simulator_ax_log_original_bytes="$(
        LC_ALL=C wc -c < "$simulator_ax_log_raw" | tr -d '[:space:]'
      )"
      /usr/bin/tail -c 1048576 "$simulator_ax_log_raw" \
        > "$failure_diagnostic_path/simulator-accessibility-unified.log"
      printf 'simulator_ax_log_bound=%s\n' "$?" >> "$diagnostic_status_path"
      simulator_ax_log_retained_bytes="$(
        LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-accessibility-unified.log" \
          | tr -d '[:space:]'
      )"
      printf 'simulator_ax_log_original_bytes=%s\nsimulator_ax_log_retained_bytes=%s\n' \
        "$simulator_ax_log_original_bytes" "$simulator_ax_log_retained_bytes" \
        >> "$diagnostic_status_path"
      rm -f "$simulator_ax_log_raw"
    fi
  fi
  # End K365 failure-only Simulator accessibility context.

  run_diagnostic host_launchd_system_testmanagerd \
    Scripts/run-with-timeout.sh 10 \
    /bin/launchctl print system/com.apple.testmanagerd \
    > "$failure_diagnostic_path/launchd-system-testmanagerd.txt" 2>&1
  run_diagnostic host_launchd_gui_testmanagerd \
    Scripts/run-with-timeout.sh 10 \
    /bin/launchctl print "gui/$(id -u)/com.apple.testmanagerd" \
    > "$failure_diagnostic_path/launchd-gui-testmanagerd.txt" 2>&1
  # K402: a timed-out simctl producer must not retain the final artifact sink.
  simulator_testmanagerd_raw="$(mktemp "${RUNNER_TEMP:?}/FieldEvidenceSimulatorTestmanagerd.XXXXXX")"
  simulator_testmanagerd_temp_status="$?"
  printf 'simulator_testmanagerd_temp=%s\n' "$simulator_testmanagerd_temp_status" \
    >> "$diagnostic_status_path"
  if [ "$simulator_testmanagerd_temp_status" -eq 0 ]; then
    run_diagnostic simulator_launchd_testmanagerd \
      Scripts/run-with-timeout.sh 15 \
      xcrun simctl spawn "$CI_SIMULATOR_UDID" \
        launchctl print system/com.apple.testmanagerd \
      > "$simulator_testmanagerd_raw" 2>&1
    simulator_testmanagerd_bytes_at_snapshot="$(
      LC_ALL=C wc -c < "$simulator_testmanagerd_raw" | tr -d '[:space:]'
    )"
    /usr/bin/head -c 1048576 "$simulator_testmanagerd_raw" \
      > "$failure_diagnostic_path/simulator-testmanagerd.txt"
    printf 'simulator_testmanagerd_snapshot=%s\n' "$?" >> "$diagnostic_status_path"
    simulator_testmanagerd_retained_bytes="$(
      LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-testmanagerd.txt" \
        | tr -d '[:space:]'
    )"
    printf 'simulator_testmanagerd_bytes_at_snapshot=%s\nsimulator_testmanagerd_retained_bytes=%s\nsimulator_testmanagerd_capture=bounded_snapshot_not_completion_proof\n' \
      "$simulator_testmanagerd_bytes_at_snapshot" "$simulator_testmanagerd_retained_bytes" \
      >> "$diagnostic_status_path"
    rm -f "$simulator_testmanagerd_raw"
  fi
  # End K402 closed Simulator testmanagerd snapshot.
  run_diagnostic simulator_devices \
    Scripts/run-with-timeout.sh 15 \
    xcrun simctl list devices available -j \
    > "$failure_diagnostic_path/simulator-devices.json" 2>&1

  diagnostic_reports_path="$failure_diagnostic_path/diagnostic-reports"
  mkdir -p "$diagnostic_reports_path"
  diagnostic_reports_index="$failure_diagnostic_path/diagnostic-reports-index.txt"
  : > "$diagnostic_reports_index"
  diagnostic_report_count=0
  for diagnostic_report_root in \
    "$HOME/Library/Logs/DiagnosticReports" \
    "/Library/Logs/DiagnosticReports"; do
    if [ ! -d "$diagnostic_report_root" ]; then
      continue
    fi
    while IFS= read -r diagnostic_report; do
      diagnostic_report_count=$((diagnostic_report_count + 1))
      diagnostic_report_name="$(basename "$diagnostic_report")"
      diagnostic_report_destination="$diagnostic_reports_path/$(
        printf '%03d' "$diagnostic_report_count"
      )-$diagnostic_report_name"
      diagnostic_report_original_bytes="$(
        LC_ALL=C wc -c < "$diagnostic_report" | tr -d '[:space:]'
      )"
      /usr/bin/head -c 1048576 "$diagnostic_report" \
        > "$diagnostic_report_destination"
      diagnostic_report_status="$?"
      diagnostic_report_retained_bytes=0
      if [ -f "$diagnostic_report_destination" ]; then
        diagnostic_report_retained_bytes="$(
          LC_ALL=C wc -c < "$diagnostic_report_destination" \
            | tr -d '[:space:]'
        )"
      fi
      printf '%03d\tstatus=%s\toriginal_bytes=%s\tretained_bytes=%s\tname=%s\n' \
        "$diagnostic_report_count" \
        "$diagnostic_report_status" \
        "$diagnostic_report_original_bytes" \
        "$diagnostic_report_retained_bytes" \
        "$diagnostic_report_name" \
        >> "$diagnostic_reports_index"
      if [ "$diagnostic_report_count" -ge 20 ]; then
        break
      fi
    done < <(
      find "$diagnostic_report_root" \
        -type f \
        -mmin -60 \
        \( \
          -iname '*testmanagerd*' -o \
          -iname '*xctest*' -o \
          -iname '*CoreSimulator*' \
          ${diagnostic_report_app_patterns[@]+"${diagnostic_report_app_patterns[@]}"} \
        \) \
        -print 2>/dev/null \
        | LC_ALL=C sort
    )
    if [ "$diagnostic_report_count" -ge 20 ]; then
      break
    fi
  done
  printf 'diagnostic_report_count=%s\n' "$diagnostic_report_count" \
    >> "$diagnostic_status_path"

  # H412 native container diagnostics: separate originals, failure-only and nonaccepting.
  h412_native_incident_root=""
  if [ "$h412_shared_incident_profile" = bounded ] || [ "$h412_shared_incident_profile" = rtl-string ] || [ "$h412_shared_incident_profile" = double-length ]; then
    h412_native_export_path="$failure_diagnostic_path/native-container-diagnostics"
    h412_native_now="$(date +%s)"
    h412_native_origin="${CI_BUDGET_START_EPOCH:-}"
    h412_native_total="${CI_TOTAL_BUDGET_SECONDS:-}"
    printf 'native_diagnostics_acceptance_eligible=false\nnative_diagnostics_original_layout=xcresulttool_export_diagnostics\n' >> "$diagnostic_status_path"
    if [[ "$h412_native_now" =~ ^[1-9][0-9]{0,9}$ ]] &&
       [[ "$h412_native_origin" =~ ^[1-9][0-9]{0,9}$ ]] &&
       [[ "$h412_native_total" =~ ^[1-9][0-9]{0,9}$ ]] &&
       [ "$h412_native_origin" -le "$h412_native_now" ] &&
       [ "$(( h412_native_total - (h412_native_now - h412_native_origin) ))" -ge 100 ] &&
       [ -d "$result_bundle_path" ] && [ ! -L "$result_bundle_path" ] &&
       [ -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)" ] &&
       [ ! -e "$h412_native_export_path" ] && [ ! -L "$h412_native_export_path" ]; then
      run_diagnostic native_diagnostics_help Scripts/run-with-timeout.sh 5 \
        xcrun xcresulttool help export diagnostics \
        > "$failure_diagnostic_path/native-diagnostics-help.txt" 2>&1
      h412_native_help_status="$diagnostic_status"
      if [ "$h412_native_help_status" -eq 0 ]; then
        run_diagnostic native_diagnostics_capability Scripts/run-with-timeout.sh 5 python3 - \
          "$failure_diagnostic_path/native-diagnostics-help.txt" "$CI_ARTIFACT_DIR" "$result_bundle_path" \
          "$failure_diagnostic_path" "$h412_native_export_path" <<'H412_NATIVE_CAPABILITY'
import pathlib, sys
try:
    help_path, artifact, result, diagnostic, output = map(pathlib.Path, sys.argv[1:])
    if not all(p.is_absolute() and p.resolve() == p for p in (artifact, result, diagnostic, output)):
        raise ValueError('unsafe root')
    if result != artifact / 'UISmoke.xcresult' or diagnostic != artifact / 'ui-failure-diagnostics' or output != diagnostic / 'native-container-diagnostics':
        raise ValueError('unexpected root')
    if output.exists() or output.is_symlink() or help_path.stat().st_size > 65536:
        raise ValueError('existing output or oversized help')
    text = help_path.read_text(encoding='utf-8')
    if not all(token in text for token in ('export diagnostics', '--path', '--output-path')):
        raise ValueError('installed capability unavailable')
except (OSError, ValueError, UnicodeError):
    sys.exit(64)
H412_NATIVE_CAPABILITY
        h412_native_capability_status="$diagnostic_status"
        h412_native_query_now="$(date +%s)"
        if [ "$h412_native_capability_status" -eq 0 ] &&
           [[ "$h412_native_query_now" =~ ^[1-9][0-9]{0,9}$ ]] &&
           [ "$h412_native_now" -le "$h412_native_query_now" ] &&
           [ "$(( h412_native_total - (h412_native_query_now - h412_native_origin) ))" -ge 90 ]; then
          run_diagnostic native_diagnostics_export Scripts/run-with-timeout.sh 20 \
            xcrun xcresulttool export diagnostics --path "$result_bundle_path" --output-path "$h412_native_export_path" \
            > "$failure_diagnostic_path/native-diagnostics-export.log" 2>&1
          h412_native_export_status="$diagnostic_status"
          if [ "$h412_native_export_status" -eq 0 ]; then
            run_diagnostic native_diagnostics_index Scripts/run-with-timeout.sh 5 python3 - \
              "$h412_native_export_path" <<'H412_NATIVE_INDEX' > "$failure_diagnostic_path/native-diagnostics-index.json"
import hashlib, json, os, pathlib, stat, sys
try:
    root = pathlib.Path(sys.argv[1])
    if not root.is_absolute() or root.resolve() != root or not root.is_dir() or root.is_symlink():
        raise ValueError('unsafe export root')
    rows = []
    entries = 0
    total = 0
    def walk_error(error): raise error
    for current, dirs, files in os.walk(root, followlinks=False, onerror=walk_error):
        for name in sorted(dirs + files):
            p = pathlib.Path(current) / name
            relative = p.relative_to(root)
            entries += 1
            info = p.lstat()
            if entries > 4096 or len(relative.parts) > 8 or p.resolve() != p:
                raise ValueError('export entry/path bound')
            if stat.S_ISDIR(info.st_mode):
                continue
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > 67108864:
                raise ValueError('export file type/size')
            total += info.st_size
            if total > 268435456:
                raise ValueError('export total bound')
            digest_state = hashlib.sha256()
            with p.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1048576), b''):
                    digest_state.update(chunk)
            digest = digest_state.hexdigest().upper()
            after = p.lstat()
            if (after.st_dev, after.st_ino, after.st_mode, after.st_size, after.st_mtime_ns) != (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns):
                raise ValueError('export changed during index')
            rows.append(dict(path=relative.as_posix(), bytes=info.st_size, sha256=digest))
    if not rows:
        raise ValueError('empty native export')
    print(json.dumps(dict(originalLayout=True, acceptanceEligible=False, entries=entries, bytes=total, files=rows), sort_keys=True))
except (OSError, ValueError):
    sys.exit(64)
H412_NATIVE_INDEX
            if [ "$diagnostic_status" -eq 0 ]; then h412_native_incident_root="$h412_native_export_path"; fi
          fi
        else
          printf 'native_diagnostics_export=skip-capability-or-rechecked-budget\n' >> "$diagnostic_status_path"
        fi
      fi
    else
      printf 'native_diagnostics_export=skip-input-root-or-budget\n' >> "$diagnostic_status_path"
    fi
  fi
  # End H412 native container diagnostics.

  # H408 optional incident-correlated app log; originals remain unchanged.
  if [ "${CI_RUNNER_PROVIDER:-}" = github ] &&
     [ "${CI_TASK_ID:-}" = S10.4 ] &&
     [ "${CI_S10_4_PILOT_MODE:-false}" = false ] &&
     { [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.minimum-os ] ||
       [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.accented ] ||
       [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.bounded ] ||
       [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.tall ] ||
       [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.rtl ] ||
       { [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.rtl-string ] &&
         [ "${CI_S10_4_PILOT_MODE:-}" = false ] &&
         [ "$diagnostic_probe_id" = none ] &&
         [ "${CI_S10_4_SEGMENT_ID:-}" = none ] &&
         [ "${CI_S10_4_EXECUTION_ROLE:-}" = independent ]; } || [ "$h412_shared_incident_profile" = rtl-string ]; }; then
    ips_now="$(date +%s)"
    ips_origin="${CI_BUDGET_START_EPOCH:-}"
    ips_total="${CI_TOTAL_BUDGET_SECONDS:-}"
    ips_budget=false
    if [[ "$ips_now" =~ ^[1-9][0-9]{0,9}$ ]] &&
       [[ "$ips_origin" =~ ^[1-9][0-9]{0,9}$ ]] &&
       [[ "$ips_total" =~ ^[1-9][0-9]{0,9}$ ]] &&
       [ "$ips_origin" -le "$ips_now" ] &&
       [ "$(( ips_total - (ips_now - ips_origin) ))" -ge 40 ]; then
      ips_budget=true
    fi
    if [ "$ips_budget" = true ]; then
      h412_native_incident_args=()
      if [ "$h412_shared_incident_profile" != none ]; then
        h412_native_incident_args=("$h412_native_incident_root" "$failure_diagnostic_path/native-diagnostics-index.json" "$CI_SIMULATOR_UDID")
      fi
      ips_binding="$(Scripts/run-with-timeout.sh 5 python3 - \
        "$failure_attachment_export_path" "$diagnostic_reports_path" \
        ${h412_native_incident_args[@]+"${h412_native_incident_args[@]}"} "${ips_test_started_epoch:-}" "$ips_now" <<'PY'
import datetime as dt, json, pathlib, re, sys
import hashlib, os, stat

def select(roots, start, end):
    if not re.fullmatch(r'[1-9][0-9]{0,9}',start) or not re.fullmatch(r'[1-9][0-9]{0,9}',end) or int(start)>int(end):
        return 'skip-invalid-interval'
    if len(roots) not in (2,5): return 'skip-missing-exports'
    native_roots=roots[2:]
    roots=roots[:2]
    files=[]
    entry_count=0
    for root_name in roots:
        root=pathlib.Path(root_name)
        if not root.is_dir() or root.is_symlink(): return 'skip-missing-exports'
        for p in root.iterdir():
            if entry_count>=4096: return 'skip-too-many-export-entries'
            entry_count+=1
            if p.suffix.lower()=='.ips':
                files.append(p)
                if len(files)>20: return 'skip-too-many-reports'
    # H412 accepts only a complete bounded native export index; two-root legacy behavior is unchanged.
    native_digests={}
    native_simulator=''
    if native_roots:
        native_name,index_name,native_simulator=native_roots
        if not re.fullmatch(r'[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}',native_simulator):
            return 'skip-invalid-native-simulator'
        if native_name:
            native_root=pathlib.Path(native_name)
            index_path=pathlib.Path(index_name)
            if not native_root.is_absolute() or native_root.resolve()!=native_root or not native_root.is_dir() or native_root.is_symlink():
                return 'skip-invalid-native-root'
            if native_root.name!='native-container-diagnostics' or index_path!=native_root.parent/'native-diagnostics-index.json':
                return 'skip-invalid-native-index-path'
            if index_path.is_symlink() or not index_path.is_file() or index_path.stat().st_size>4194304:
                return 'skip-invalid-native-index'
            def native_unique(pairs):
                result={}
                for key,value in pairs:
                    if key in result: raise ValueError('duplicate native index key')
                    result[key]=value
                return result
            index=json.loads(index_path.read_text(encoding='utf-8'),object_pairs_hook=native_unique)
            if set(index)!=set(('originalLayout','acceptanceEligible','entries','bytes','files')) or index['originalLayout'] is not True or index['acceptanceEligible'] is not False or not isinstance(index['files'],list):
                return 'skip-invalid-native-index'
            expected={}
            for row in index['files']:
                if not isinstance(row,dict) or set(row)!=set(('path','bytes','sha256')):
                    return 'skip-invalid-native-index'
                name=row['path']
                if not isinstance(name,str) or name in expected or not name or '\\' in name or pathlib.PurePosixPath(name).is_absolute() or any(part in ('','.','..') for part in name.split('/')):
                    return 'skip-invalid-native-index-path'
                if type(row['bytes']) is not int or not 0<=row['bytes']<=67108864 or not isinstance(row['sha256'],str) or not re.fullmatch(r'[0-9A-F]{64}',row['sha256']):
                    return 'skip-invalid-native-index'
                expected[name]=row
            observed={}
            native_count=0
            native_bytes=0
            def walk_error(error): raise error
            for current,dirs,names in os.walk(native_root,followlinks=False,onerror=walk_error):
                for name in sorted(dirs+names):
                    p=pathlib.Path(current)/name
                    relative=p.relative_to(native_root)
                    native_count+=1
                    entry_count+=1
                    if entry_count>4096 or len(relative.parts)>8 or p.resolve()!=p:
                        return 'skip-native-entry-bound'
                    info=p.lstat()
                    if stat.S_ISDIR(info.st_mode): continue
                    if not stat.S_ISREG(info.st_mode) or info.st_nlink!=1 or info.st_size>67108864:
                        return 'skip-invalid-native-file'
                    native_bytes+=info.st_size
                    if native_bytes>268435456: return 'skip-native-byte-bound'
                    key=relative.as_posix()
                    if key not in expected or expected[key]['bytes']!=info.st_size:
                        return 'skip-native-index-mismatch'
                    observed[key]=info.st_size
                    if p.suffix.lower()=='.ips':
                        files.append(p)
                        native_digests[p]=expected[key]['sha256']
                        if len(files)>20: return 'skip-too-many-reports'
            if not observed or set(observed)!=set(expected) or type(index['entries']) is not int or type(index['bytes']) is not int or native_count!=index['entries'] or native_bytes!=index['bytes']:
                return 'skip-native-index-mismatch'
    candidates=[]
    canonical_reports=set()
    def unique_object(pairs):
        result={}
        for key,value in pairs:
            if key in result: raise ValueError('duplicate key')
            result[key]=value
        return result
    decoder=json.JSONDecoder(object_pairs_hook=unique_object)
    def stamp(s):
        if not isinstance(s,str) or len(s)>40: raise ValueError()
        return dt.datetime.strptime(s,'%Y-%m-%d %H:%M:%S.%f %z').timestamp()
    for p in files:
        if p.is_symlink() or not p.is_file() or p.stat().st_size>1048576: return 'skip-invalid-report'
        try:
            with p.open('rb') as stream: raw=stream.read(1048577)
            if len(raw)>1048576: return 'skip-invalid-report'
            if p in native_digests and hashlib.sha256(raw).hexdigest().upper()!=native_digests[p]:
                return 'skip-native-report-hash-mismatch'
            text=raw.decode('utf-8-sig')
            header,offset=decoder.raw_decode(text)
            tail=text[offset:].lstrip(); body,offset=decoder.raw_decode(tail)
            if tail[offset:].strip(): raise ValueError()
            if not isinstance(header,dict) or not isinstance(body,dict): raise ValueError()
            if header.get('bundleID')!='com.palatis3.fieldrecord': continue
            if body.get('procName')!='FieldEvidenceApp' or body.get('bundleInfo',{}).get('CFBundleIdentifier')!='com.palatis3.fieldrecord': raise ValueError()
            incident=body.get('incident',''); pid=body.get('pid')
            if not re.fullmatch(r'[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}',incident) or header.get('incident_id')!=incident: raise ValueError()
            if type(pid) is not int or not 0<pid<=2147483647: raise ValueError()
            if native_roots:
                process_path=body.get('procPath')
                if not isinstance(process_path,str) or len(process_path)>4096: raise ValueError()
                process_components=process_path.split('/')
                if len(process_components)!=15 or process_components[0]!='' or '\\' in process_path or any(ord(c)<32 or ord(c)==127 for c in process_path):
                    continue
                if any(component in ('','.','..') for component in process_components[1:]):
                    continue
                if process_components[1]!='Users' or process_components[3:7]!=['Library','Developer','CoreSimulator','Devices'] or process_components[8:12]!=['data','Containers','Bundle','Application'] or process_components[13:]!=['FieldEvidenceApp.app','FieldEvidenceApp']:
                    continue
                native_path_uuid=r'[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'
                if re.fullmatch(native_path_uuid,process_components[7]) is None or re.fullmatch(native_path_uuid,process_components[12]) is None or process_components[7].upper()!=native_simulator:
                    continue
            launch=stamp(body.get('procLaunch')); capture=stamp(body.get('captureTime'))
            if not int(start)<=launch<=capture<=int(end): continue
            # Collapse only complete validated parsed records, preserving scalar types.
            canonical=json.dumps([header,body],sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False)
            if canonical not in canonical_reports:
                canonical_reports.add(canonical)
                candidates.append((pid,incident,body['procLaunch'],body['captureTime'],int(capture)))
        except (ValueError,TypeError,AttributeError,UnicodeError,OSError,RecursionError): return 'skip-invalid-report'
    if not candidates: return 'skip-no-current-app-incident'
    if len(candidates)!=1: return 'skip-ambiguous-incidents'
    pid,incident,launch,capture,capture_epoch=candidates[0]
    return f'{pid}\t{incident}\t{launch}\t{capture}\t{capture_epoch}'

if __name__=='__main__':
    try: print(select(sys.argv[1:-2], sys.argv[-2], sys.argv[-1]))
    except (OSError,ValueError): print('skip-input-error')
PY
      )"
      ips_parser_status="$?"
      IFS=$'\t' read -r ips_pid ips_incident ips_launch ips_capture ips_capture_epoch ips_extra <<< "$ips_binding"
      if [[ "$ips_capture_epoch" =~ ^[1-9][0-9]{0,9}$ ]] && [ -z "$ips_extra" ]; then
        ips_binding="$(printf '%s\t%s\t%s\t%s' "$ips_pid" "$ips_incident" "$ips_launch" "$ips_capture")"
      fi
      printf 'ips_parser_status=%s\nips_binding=%s\nips_capture_epoch=%s\n' "$ips_parser_status" "$ips_binding" "$ips_capture_epoch" >> "$diagnostic_status_path"
      if [ "$ips_parser_status" -eq 0 ] && [[ "$ips_pid" =~ ^[1-9][0-9]{0,9}$ ]] &&
         [ "$ips_pid" -le 2147483647 ]; then
        ips_binding_now="$ips_now"
        ips_now="$(date +%s)"
        ips_origin="${CI_BUDGET_START_EPOCH:-}"
        ips_total="${CI_TOTAL_BUDGET_SECONDS:-}"
        ips_query_budget=false
        if [[ "$ips_now" =~ ^[1-9][0-9]{0,9}$ ]] &&
           [[ "$ips_origin" =~ ^[1-9][0-9]{0,9}$ ]] &&
           [[ "$ips_total" =~ ^[1-9][0-9]{0,9}$ ]] &&
           [ "$ips_origin" -le "$ips_now" ] &&
           [ "$ips_binding_now" -le "$ips_now" ] &&
           [ "$(( ips_total - (ips_now - ips_origin) ))" -ge 35 ]; then
          ips_query_budget=true
        fi
        if [ "$ips_query_budget" = true ]; then
        ips_window_valid=true
        ips_lookback_minutes=10
        ips_window_policy=default-ten-minute
        if [ "${CI_S10_4_SHARD_ID:-}" = s10.4.minimum.rtl ]; then
          ips_window_policy=validated-test-start-age-capped-ten-minute
          ips_window_valid=false
          if [[ "$ips_capture_epoch" =~ ^[1-9][0-9]{0,9}$ ]] &&
             [ -z "$ips_extra" ] && [ "$ips_capture_epoch" -le "$ips_now" ]; then
            ips_incident_age="$(( ips_now - ips_capture_epoch ))"
            if [ "$ips_incident_age" -le 599 ] &&
               [[ "$ips_test_started_epoch" =~ ^[1-9][0-9]{0,9}$ ]] &&
               [ "$ips_test_started_epoch" -le "$ips_capture_epoch" ]; then
              ips_test_age="$(( ips_now - ips_test_started_epoch ))"
              ips_lookback_minutes="$(( ips_test_age / 60 + 1 ))"
              if [ "$ips_lookback_minutes" -gt 10 ]; then ips_lookback_minutes=10; fi
              ips_window_valid=true
              printf 'ips_window_test_started_epoch=%s\n' "$ips_test_started_epoch" >> "$diagnostic_status_path"
            fi
          fi
        fi
        if [ "$ips_window_valid" = true ]; then
        ips_lookback_seconds="$(( ips_lookback_minutes * 60 ))"
        ips_requested_lower_bound_epoch="$(( ips_now - ips_lookback_seconds ))"
        ips_raw="$(mktemp "${RUNNER_TEMP:?}/FieldEvidenceIncidentLog.XXXXXX")"
        if [ "$?" -eq 0 ]; then
          printf 'ips_query_started_utc=%s\nips_query_lookback_seconds=%s\nips_window_policy=%s\nips_window_computed_epoch=%s\nips_requested_lower_bound_epoch=%s\nips_window_bound=rolling_request_not_confirmed_coverage\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$ips_lookback_seconds" "$ips_window_policy" \
            "$ips_now" "$ips_requested_lower_bound_epoch" >> "$diagnostic_status_path"
          run_diagnostic ips_app_log Scripts/run-with-timeout.sh 25 \
            xcrun simctl spawn "$CI_SIMULATOR_UDID" log show \
              --last "${ips_lookback_minutes}m" --style compact \
              --predicate "process == \"FieldEvidenceApp\" AND processIdentifier == $ips_pid" \
            > "$ips_raw" 2>&1
          ips_query_status="$diagnostic_status"
          ips_snapshot_bytes="$(LC_ALL=C wc -c < "$ips_raw" | tr -d '[:space:]')"
          /usr/bin/head -c "$ips_snapshot_bytes" "$ips_raw" | /usr/bin/tail -c 1048576 \
            > "$failure_diagnostic_path/simulator-incident-app.log"
          ips_snapshot_status="$?"
          ips_retained_bytes="$(LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-incident-app.log" | tr -d '[:space:]')"
          printf 'ips_query_ended_utc=%s\nips_query_status=%s\nips_snapshot_status=%s\nips_snapshot_bytes=%s\nips_retained_bytes=%s\nips_capture=bounded_snapshot_not_completion_proof\n' \
            "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$ips_query_status" "$ips_snapshot_status" \
            "$ips_snapshot_bytes" "$ips_retained_bytes" >> "$diagnostic_status_path"
          if [ "$ips_snapshot_bytes" -gt 1048576 ]; then printf 'ips_truncated=true\n' >> "$diagnostic_status_path"; fi
          if [ "$ips_query_status" -ne 0 ] || [ "$ips_snapshot_status" -ne 0 ] || [ "$ips_retained_bytes" -eq 0 ]; then
            printf 'ips_incomplete=true\n' >> "$diagnostic_status_path"
          fi
          ips_prefix_limit="$ips_snapshot_bytes"
          if [ "$ips_prefix_limit" -gt 1048576 ]; then ips_prefix_limit=1048576; fi
          /usr/bin/head -c "$ips_prefix_limit" "$ips_raw" \
            > "$failure_diagnostic_path/simulator-incident-app-prefix.log"
          ips_prefix_status="$?"
          ips_prefix_bytes="$(LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-incident-app-prefix.log" | tr -d '[:space:]')"
          ips_tail_snapshot_start=0
          if [ "$ips_snapshot_bytes" -gt 1048576 ]; then
            ips_tail_snapshot_start="$(( ips_snapshot_bytes - 1048576 ))"
          fi
          ips_prefix_tail_overlap=0
          if [ "$ips_prefix_bytes" -gt "$ips_tail_snapshot_start" ]; then
            ips_prefix_tail_overlap="$(( ips_prefix_bytes - ips_tail_snapshot_start ))"
          fi
          printf 'ips_prefix_status=%s\nips_prefix_bytes=%s\nips_prefix_start_byte=0\nips_prefix_end_byte=%s\nips_tail_snapshot_start_byte=%s\nips_tail_snapshot_end_byte=%s\nips_prefix_tail_overlap_bytes=%s\nips_prefix_capture=bounded_snapshot_not_completion_proof\n' \
            "$ips_prefix_status" "$ips_prefix_bytes" "$ips_prefix_bytes" \
            "$ips_tail_snapshot_start" "$ips_snapshot_bytes" "$ips_prefix_tail_overlap" \
            >> "$diagnostic_status_path"
          if [ "$ips_query_status" -ne 0 ] || [ "$ips_prefix_status" -ne 0 ] || \
             [ "$ips_prefix_bytes" -ne "$ips_prefix_limit" ] || [ "$ips_prefix_bytes" -eq 0 ]; then
            printf 'ips_prefix_incomplete=true\n' >> "$diagnostic_status_path"
          fi
          rm -f "$ips_raw"
          # K479 conditional incident-window observation; primary collection is unchanged.
          printf 'ips_adjacent_acceptance_eligible=false\n' >> "$diagnostic_status_path"
          ips_adjacent_cohort=false
          if [ "$ips_query_status" = 124 ]; then
            if [ "${CI_RUNNER_PROVIDER:-}" = github ] &&
               [ "${CI_TASK_ID:-}" = S10.4 ] &&
               [ "${CI_S10_4_PILOT_MODE:-}" = false ] &&
               [ "${diagnostic_probe_id:-}" = none ] &&
               [ "${CI_S10_4_SEGMENT_ID:-}" = none ] &&
               [ "${CI_S10_4_EXECUTION_ROLE:-}" = independent ] &&
               [ "${CI_S10_4_DEVICE_PROFILE_ID:-}" = iphone-se-3-ios-18.0-minimum ]; then
              case "${CI_S10_4_SHARD_ID:-}:${CI_S10_4_SHARD_ORDINAL:-}:${CI_S10_4_REQUIREMENT_ID:-}" in
                s10.4.minimum.minimum-os:8:minimum_os | s10.4.minimum.bounded:14:bounded | \
                s10.4.minimum.tall:12:tall | s10.4.minimum.rtl:10:rtl | s10.4.minimum.rtl-string:11:rtl_string)
                  ips_adjacent_cohort=true ;;
              esac
            elif [ "${CI_RUNNER_PROVIDER:-}" = github ] &&
                 [ "${CI_TASK_ID:-}" = S10.4 ] &&
                 [ "${CI_S10_4_PILOT_MODE:-}" = false ] &&
                 [ "${diagnostic_probe_id:-}" = none ] &&
                 [ "${CI_S10_4_SEGMENT_ID:-}" = none ] &&
                 [ "${CI_S10_4_EXECUTION_ROLE:-}" = payload-consumer ] &&
                 [ "${CI_S10_4_SHARED_BUILD_MODE:-}" = consumer ] &&
                 [ "${CI_S10_4_SHARED_EXECUTION_LANE:-}" = github-xcode-26.6-shared-build-acceptance ] &&
                 [ "${CI_S10_4_DEVICE_PROFILE_ID:-}" = iphone-se-3-ios-18.0-minimum ] &&
                 [ "${CI_S10_4_SHARD_ID:-}:${CI_S10_4_SHARD_ORDINAL:-}:${CI_S10_4_REQUIREMENT_ID:-}" = s10.4.minimum.bounded:14:bounded ] &&
                 [ "${WORKER_S10_4_MINIMUM_SEGMENT_ID:-}" = minimum-segment-2 ] &&
                 [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_ID:-}" = minimum-segment-2 ] &&
                 [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_EXECUTION_LANE:-}" = github-xcode-26.6-shared-build-acceptance ] &&
                 [ -n "${GITHUB_SHA:-}" ] && [ -n "${GITHUB_REF:-}" ] &&
                 [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_HEAD:-}" = "$GITHUB_SHA" ] &&
                 [ "${TEST_RUNNER_CI_S10_4_MINIMUM_SEGMENT_REF:-}" = "$GITHUB_REF" ]; then
              ips_adjacent_cohort=true
            elif [ "$h412_shared_incident_profile" = rtl-string ]; then
              ips_adjacent_cohort=true
            fi
            if [ "$ips_adjacent_cohort" != true ]; then
              printf 'ips_adjacent_log=skip-ineligible-ordinary-tuple\n' >> "$diagnostic_status_path"
            fi
          else
            printf 'ips_adjacent_log=skip-primary-query-not-timeout\n' >> "$diagnostic_status_path"
          fi
          if [ "$ips_adjacent_cohort" = true ]; then
            ips_adjacent_now="$(date +%s)"
            ips_adjacent_origin="${CI_BUDGET_START_EPOCH:-}"
            ips_adjacent_total="${CI_TOTAL_BUDGET_SECONDS:-}"
            ips_adjacent_valid=false
            if [[ "$ips_pid" =~ ^[1-9][0-9]{0,9}$ ]] && [ "$ips_pid" -le 2147483647 ] &&
               [[ "$ips_capture_epoch" =~ ^[1-9][0-9]{0,9}$ ]] && [ -z "${ips_extra:-}" ] &&
               [[ "$ips_test_started_epoch" =~ ^[1-9][0-9]{0,9}$ ]] &&
               [[ "$ips_adjacent_now" =~ ^[1-9][0-9]{0,9}$ ]] &&
               [[ "$ips_adjacent_origin" =~ ^[1-9][0-9]{0,9}$ ]] &&
               [[ "$ips_adjacent_total" =~ ^[1-9][0-9]{0,9}$ ]] &&
               [ "$ips_adjacent_origin" -le "$ips_test_started_epoch" ] &&
               [ "$ips_test_started_epoch" -le "$ips_capture_epoch" ] &&
               [ "$ips_capture_epoch" -le "$ips_adjacent_now" ] &&
               [ "$(( ips_adjacent_now - ips_capture_epoch ))" -le 600 ] &&
               [ "$(( ips_adjacent_total - (ips_adjacent_now - ips_adjacent_origin) ))" -ge 35 ]; then
              ips_adjacent_start="$(( ips_capture_epoch - 30 ))"
              if [ "$ips_adjacent_start" -lt "$ips_test_started_epoch" ]; then
                ips_adjacent_start="$ips_test_started_epoch"
              fi
              ips_adjacent_end="$(( ips_capture_epoch + 2 ))"
              if [ "$ips_adjacent_start" -gt 0 ] && [ "$ips_adjacent_start" -lt "$ips_adjacent_end" ] &&
                 [ "$ips_adjacent_end" -le "$ips_adjacent_now" ] &&
                 [ "$(( ips_adjacent_end - ips_adjacent_start ))" -le 32 ]; then
                ips_adjacent_valid=true
              fi
            fi
            if [ "$ips_adjacent_valid" = true ]; then
              ips_adjacent_dates="$(Scripts/run-with-timeout.sh 5 python3 - "$ips_adjacent_start" "$ips_adjacent_end" <<'PY'
import datetime as dt, re, sys
try:
    if len(sys.argv) != 3 or any(re.fullmatch(r'[1-9][0-9]{0,9}', x) is None for x in sys.argv[1:]):
        raise ValueError()
    start, end = map(int, sys.argv[1:])
    if not start < end or end - start > 32:
        raise ValueError()
    print('\t'.join(dt.datetime.fromtimestamp(x, dt.timezone.utc).strftime('%Y-%m-%d %H:%M:%S%z') for x in (start, end)))
except (ValueError, OverflowError, OSError):
    sys.exit(64)
PY
              )"
              ips_adjacent_format_status="$?"
              IFS=$'\t' read -r ips_adjacent_start_utc ips_adjacent_end_utc ips_adjacent_extra <<< "$ips_adjacent_dates"
              printf 'ips_adjacent_format_status=%s\n' "$ips_adjacent_format_status" >> "$diagnostic_status_path"
              if [ "$ips_adjacent_format_status" -eq 0 ] && [ -z "$ips_adjacent_extra" ] &&
                 [[ "$ips_adjacent_start_utc" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\+0000$ ]] &&
                 [[ "$ips_adjacent_end_utc" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\+0000$ ]] &&
                 [ "$ips_adjacent_dates" = "$ips_adjacent_start_utc"$'\t'"$ips_adjacent_end_utc" ]; then
                ips_adjacent_query_now="$(date +%s)"
                if [[ "$ips_adjacent_query_now" =~ ^[1-9][0-9]{0,9}$ ]] &&
                   [ "$ips_adjacent_now" -le "$ips_adjacent_query_now" ] &&
                   [ "$ips_adjacent_end" -le "$ips_adjacent_query_now" ] &&
                   [ "$(( ips_adjacent_query_now - ips_capture_epoch ))" -le 600 ] &&
                   [ "$(( ips_adjacent_total - (ips_adjacent_query_now - ips_adjacent_origin) ))" -ge 35 ]; then
                  ips_adjacent_raw="$(mktemp "${RUNNER_TEMP:?}/FieldEvidenceIncidentWindow.XXXXXX")"
                  if [ "$?" -eq 0 ]; then
                    printf 'ips_adjacent_pid=%s\nips_adjacent_capture_epoch=%s\nips_adjacent_test_start_epoch=%s\nips_adjacent_start_epoch=%s\nips_adjacent_end_epoch=%s\nips_adjacent_start_utc=%s\nips_adjacent_end_utc=%s\nips_adjacent_query_epoch=%s\nips_adjacent_window_bound=requested_interval_not_confirmed_coverage\n' \
                      "$ips_pid" "$ips_capture_epoch" "$ips_test_started_epoch" "$ips_adjacent_start" "$ips_adjacent_end" \
                      "$ips_adjacent_start_utc" "$ips_adjacent_end_utc" "$ips_adjacent_query_now" >> "$diagnostic_status_path"
                    run_diagnostic ips_adjacent_app_log Scripts/run-with-timeout.sh 25 \
                      xcrun simctl spawn "$CI_SIMULATOR_UDID" log show \
                        --start "$ips_adjacent_start_utc" --end "$ips_adjacent_end_utc" --style compact \
                        --predicate "process == \"FieldEvidenceApp\" AND processIdentifier == $ips_pid" \
                      > "$ips_adjacent_raw" 2>&1
                    ips_adjacent_query_status="$diagnostic_status"
                    ips_adjacent_snapshot_bytes="$(LC_ALL=C wc -c < "$ips_adjacent_raw" | tr -d '[:space:]')"
                    /usr/bin/head -c "$ips_adjacent_snapshot_bytes" "$ips_adjacent_raw" | /usr/bin/tail -c 1048576 \
                      > "$failure_diagnostic_path/simulator-incident-window-app.log"
                    ips_adjacent_snapshot_status="$?"
                    ips_adjacent_retained_bytes="$(LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-incident-window-app.log" | tr -d '[:space:]')"
                    ips_adjacent_prefix_limit="$ips_adjacent_snapshot_bytes"
                    if [ "$ips_adjacent_prefix_limit" -gt 1048576 ]; then ips_adjacent_prefix_limit=1048576; fi
                    /usr/bin/head -c "$ips_adjacent_prefix_limit" "$ips_adjacent_raw" \
                      > "$failure_diagnostic_path/simulator-incident-window-app-prefix.log"
                    ips_adjacent_prefix_status="$?"
                    ips_adjacent_prefix_bytes="$(LC_ALL=C wc -c < "$failure_diagnostic_path/simulator-incident-window-app-prefix.log" | tr -d '[:space:]')"
                    ips_adjacent_tail_start=0
                    if [ "$ips_adjacent_snapshot_bytes" -gt 1048576 ]; then
                      ips_adjacent_tail_start="$(( ips_adjacent_snapshot_bytes - 1048576 ))"
                    fi
                    ips_adjacent_overlap=0
                    if [ "$ips_adjacent_prefix_bytes" -gt "$ips_adjacent_tail_start" ]; then
                      ips_adjacent_overlap="$(( ips_adjacent_prefix_bytes - ips_adjacent_tail_start ))"
                    fi
                    ips_adjacent_truncated=false
                    if [ "$ips_adjacent_snapshot_bytes" -gt 1048576 ]; then ips_adjacent_truncated=true; fi
                    ips_adjacent_incomplete=false
                    if [ "$ips_adjacent_query_status" -ne 0 ] || [ "$ips_adjacent_snapshot_status" -ne 0 ] ||
                       [ "$ips_adjacent_prefix_status" -ne 0 ] || [ "$ips_adjacent_retained_bytes" -eq 0 ] ||
                       [ "$ips_adjacent_prefix_bytes" -ne "$ips_adjacent_prefix_limit" ]; then
                      ips_adjacent_incomplete=true
                    fi
                    printf 'ips_adjacent_query_ended_utc=%s\nips_adjacent_query_status=%s\nips_adjacent_snapshot_status=%s\nips_adjacent_snapshot_bytes=%s\nips_adjacent_retained_bytes=%s\nips_adjacent_prefix_status=%s\nips_adjacent_prefix_bytes=%s\nips_adjacent_prefix_start_byte=0\nips_adjacent_prefix_end_byte=%s\nips_adjacent_tail_start_byte=%s\nips_adjacent_tail_end_byte=%s\nips_adjacent_prefix_tail_overlap_bytes=%s\nips_adjacent_truncated=%s\nips_adjacent_incomplete=%s\nips_adjacent_capture=bounded_snapshot_not_completion_proof\n' \
                      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$ips_adjacent_query_status" "$ips_adjacent_snapshot_status" \
                      "$ips_adjacent_snapshot_bytes" "$ips_adjacent_retained_bytes" "$ips_adjacent_prefix_status" \
                      "$ips_adjacent_prefix_bytes" "$ips_adjacent_prefix_bytes" "$ips_adjacent_tail_start" "$ips_adjacent_snapshot_bytes" \
                      "$ips_adjacent_overlap" "$ips_adjacent_truncated" "$ips_adjacent_incomplete" >> "$diagnostic_status_path"
                    rm -f "$ips_adjacent_raw"
                  else
                    printf 'ips_adjacent_log=skip-temp-error\n' >> "$diagnostic_status_path"
                  fi
                else
                  printf 'ips_adjacent_log=skip-invalid-or-insufficient-rechecked-budget\n' >> "$diagnostic_status_path"
                fi
              else
                printf 'ips_adjacent_log=skip-date-format-error\n' >> "$diagnostic_status_path"
              fi
            else
              printf 'ips_adjacent_log=skip-invalid-window-or-budget\n' >> "$diagnostic_status_path"
            fi
          fi
          # End K479 conditional incident-window observation.
        else
          printf 'ips_app_log=skip-temp-error\n' >> "$diagnostic_status_path"
        fi
        else
          printf 'ips_app_log=skip-invalid-or-stale-incident-window\nips_window_acceptance_eligible=false\n' >> "$diagnostic_status_path"
        fi
        else
          printf 'ips_app_log=skip-invalid-or-insufficient-rechecked-budget\n' >> "$diagnostic_status_path"
        fi
      else
        printf 'ips_app_log=skip-no-validated-binding\n' >> "$diagnostic_status_path"
      fi
    else
      printf 'ips_app_log=skip-invalid-or-insufficient-budget\n' >> "$diagnostic_status_path"
    fi
  fi
  # End H408 optional incident-correlated app log.
  exit "$xcodebuild_status"
fi

test -d "$result_bundle_path"
test -n "$(find "$result_bundle_path" -mindepth 1 -print -quit)"

mkdir -p "$attachment_export_path"
test -d "$attachment_export_path"
test ! -L "$attachment_export_path"
xcrun xcresulttool export attachments \
  --path "$result_bundle_path" \
  --output-path "$attachment_export_path"

test -f "$attachment_manifest_path"
test ! -L "$attachment_manifest_path"
test -s "$attachment_manifest_path"

if [ "$diagnostic_mode" = true ]; then
  diagnostic_artifact_path="$CI_ARTIFACT_DIR/s10-4-diagnostics/$diagnostic_probe_id"
  test ! -e "$diagnostic_artifact_path"
  test ! -L "$diagnostic_artifact_path"
  mkdir -p "$diagnostic_artifact_path"
  cp -R "$attachment_export_path" "$diagnostic_artifact_path/ui-attachments"
  test -f "$diagnostic_artifact_path/ui-attachments/manifest.json"
  test ! -L "$diagnostic_artifact_path/ui-attachments/manifest.json"
  test -s "$diagnostic_artifact_path/ui-attachments/manifest.json"
  printf 'S10_4_DIAGNOSTIC_ARTIFACTS probeID=%s attachmentPath=%s\n' \
    "$diagnostic_probe_id" "$diagnostic_artifact_path/ui-attachments"
  exit 0
fi

if ! selected_attachment="$(
  jq -er \
    --arg smokeID "${WORKER_S10_4_MINIMUM_CORE_SMOKE_ID:-none}" \
    --arg selectedTestClass "$selected_test_class" '
      if type != "array"
      then error("attachment manifest root must be an array")
      else .
      end
      | [
          .[]
          | select(
              type == "object"
              and (.testIdentifier | type == "string")
              and (
                (.testIdentifier | split("/")) as $parts
                | ($parts | length) == 2
                  and $parts[0] == $selectedTestClass
                  and ($parts[1] | length) > 0
              )
              and (.attachments | type == "array")
            )
          | .attachments[]
          | select(
              type == "object"
              and .isAssociatedWithFailure == false
              and (.suggestedHumanReadableName | type == "string")
              and (.suggestedHumanReadableName | length) > 0
              and ($smokeID == "none" or .suggestedHumanReadableName == "S10.4 minimum core smoke terminal"
                   or (.suggestedHumanReadableName | test("^S10[.]4 minimum core smoke terminal_0_[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}[.]png$")))
              and (.exportedFileName | type == "string")
              and (.exportedFileName | length > 4)
              and (.exportedFileName | endswith(".png"))
              and (.exportedFileName | contains("/") | not)
              and (.exportedFileName | contains("\\") | not)
              and (.exportedFileName | contains("\u0000") | not)
              and (.exportedFileName | contains("\n") | not)
              and (.exportedFileName | contains("\r") | not)
              and (.exportedFileName != ".")
              and (.exportedFileName != "..")
            )
        ] as $matches
      | if ($matches | length) == 1
        then $matches[0].exportedFileName
        else error("expected exactly one retained non-failure PNG attachment for the selected UI test class")
        end
    ' "$attachment_manifest_path"
)"; then
  printf 'failed to select the exact retained UI screenshot attachment\n' >&2
  exit 65
fi

selected_attachment_path="$attachment_export_path/$selected_attachment"
test -f "$selected_attachment_path"
test ! -L "$selected_attachment_path"
test -s "$selected_attachment_path"
test "$(LC_ALL=C od -An -tx1 -N8 "$selected_attachment_path" \
  | tr -d '[:space:]' \
  | tr '[:upper:]' '[:lower:]')" = \
  "89504e470d0a1a0a"

cp "$selected_attachment_path" "$screenshot_path"
test -f "$screenshot_path"
test ! -L "$screenshot_path"
test -s "$screenshot_path"
cmp -s "$selected_attachment_path" "$screenshot_path"
printf 'selected UI screenshot class: %s\n' "$selected_test_class"
printf 'selected UI screenshot attachment: %s\n' "$selected_attachment"
