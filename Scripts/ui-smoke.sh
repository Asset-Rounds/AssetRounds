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

if [ "$pilot_consumer" = true ]; then
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
    printf 'host_unified_log_bound=%s\n' "$?" >> "$diagnostic_status_path"
    host_unified_log_retained_bytes="$(
      LC_ALL=C wc -c < "$failure_diagnostic_path/host-unified.log" \
        | tr -d '[:space:]'
    )"
  fi
  printf 'host_unified_log_original_bytes=%s\n' \
    "$host_unified_log_original_bytes" >> "$diagnostic_status_path"
  printf 'host_unified_log_retained_bytes=%s\n' \
    "$host_unified_log_retained_bytes" >> "$diagnostic_status_path"
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
  run_diagnostic simulator_launchd_testmanagerd \
    Scripts/run-with-timeout.sh 15 \
    xcrun simctl spawn "$CI_SIMULATOR_UDID" \
      launchctl print system/com.apple.testmanagerd \
    > "$failure_diagnostic_path/simulator-testmanagerd.txt" 2>&1
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

if ! selected_attachment="$(
  jq -er \
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
