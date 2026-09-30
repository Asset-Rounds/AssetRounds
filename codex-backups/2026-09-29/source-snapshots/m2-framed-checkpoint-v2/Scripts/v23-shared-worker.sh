#!/bin/bash
# Development-only V23 shared coverage worker steps for .github/workflows/ios-ci-shared-worker.yml.
#
# Each subcommand is the V23 GitHub macos-26 path of the ordinary worker step of the
# same name in ios-ci-worker.yml, which stays unchanged for every other route. The
# S10.4, pilot, Bitrise, GetMac and UI branches never apply to this route, so they
# are absent here; the admission, selection, build, test and evidence commands are
# the same checked-in scripts the ordinary worker runs.
set -euo pipefail

require_route() {
  test "${CI_RUNNER_PROVIDER:-}:${CI_RUNNER_LABEL:-}" = github:macos-26
  test "${CI_NATIVE_ACCEPTANCE_CONTRACT:-}" = v23.integration.current-native.v1
  test "${NATIVE_SELECTION_ID:-}" = v23-shared-coverage-d50x
  test "${DISPATCH_NATIVE_SELECTION_ID:-}" = "$NATIVE_SELECTION_ID"
  case "${V23_SHARED_ROLE:-}:${V23_PARTITION_ID:-}:${V23_PARTITION_TIER:-}" in
    producer::) ;;
    consumer:S[0-9][0-9]:D50C | consumer:S[0-9][0-9]:D90S) ;;
    *) printf 'invalid V23 shared coverage role, partition or tier\n' >&2; exit 65 ;;
  esac
  test -n "${CI_ARTIFACT_DIR:-}"
  test -n "${GITHUB_ENV:-}"
}

# Validate task selection and timeout tier.
admit() {
  require_route
  local path
  for path in Scripts/ci-selection.json Scripts/ci-selection-map.json Scripts/ci-worker-selection.jq \
      Scripts/run-with-timeout.sh Scripts/build-smoke.sh Scripts/test-smoke.sh \
      Scripts/validate-required-evidence.sh; do
    test -f "$path"
  done
  python3 Scripts/v23-native-ci.py admit --stage worker
  local selection="$CI_ARTIFACT_DIR/ci-selection.selected.json"
  python3 Scripts/v23-native-ci.py select --output "$selection"
  cp Scripts/ci-selection-map.json "$CI_ARTIFACT_DIR/ci-selection-map.json"
  jq -e -f Scripts/ci-worker-selection.jq "$selection" > /dev/null
  local run_ui tier
  run_ui="$(jq -r '.runUISmoke | tostring' "$selection")"
  test "$DISPATCH_RUN_UI_SMOKE" = "$run_ui"
  test "$run_ui" = false
  tier="$(jq -r '.tier' "$selection")"
  # The caller's tier set this job's timeout; it must be the partition's own tier.
  case "$V23_SHARED_ROLE:$tier:$V23_PARTITION_TIER" in
    producer:D40P: | consumer:D50C:D50C | consumer:D90S:D90S) ;;
    *) exit 65 ;;
  esac
  {
    printf 'CI_SELECTION_PATH=%s\n' "$selection"
    printf 'CI_TASK_ID=%s\n' "$(jq -r '.taskID' "$selection")"
    printf 'CI_TIER=%s\n' "$tier"
    printf 'CI_SELECTOR_RUN_UI_SMOKE=%s\nCI_RUN_UI_SMOKE=%s\n' "$run_ui" "$run_ui"
    printf 'CI_SETUP_ARTIFACT_TIMEOUT_SECONDS=%s\n' "$(jq -r '.setupArtifactTimeoutSeconds' "$selection")"
    printf 'CI_BUILD_TIMEOUT_SECONDS=%s\n' "$(jq -r '.buildTimeoutSeconds' "$selection")"
    printf 'CI_TEST_TIMEOUT_SECONDS=%s\n' "$(jq -r '.testTimeoutSeconds' "$selection")"
    printf 'CI_UI_TIMEOUT_SECONDS=%s\n' "$(jq -r '.uiTimeoutSeconds' "$selection")"
    printf 'CI_TOTAL_BUDGET_SECONDS=%s\n' "$(jq -r '.totalBudgetSeconds' "$selection")"
    printf 'SIMULATOR_RUNTIME_BUILD=23C54\n'
  } >> "$GITHUB_ENV"
  cp Scripts/ci-selection.json "$CI_ARTIFACT_DIR/ci-selection.json"
  printf 'task_id=%s\ntier=%s\ndispatch_run_ui_smoke=%s\ns10_4_shard_id=none\ns10_4_segment_id=none\ns10_4_execution_role=independent\ns10_4_pilot_mode=false\nv23_shared_role=%s\nv23_partition_id=%s\n' \
    "$(jq -r '.taskID' "$selection")" "$tier" "$DISPATCH_RUN_UI_SMOKE" "$V23_SHARED_ROLE" "$V23_PARTITION_ID" \
    | tee "$CI_ARTIFACT_DIR/ci-selection-validation.txt"
}

# Verify pinned toolchain, shared scheme, and simulator.
toolchain() {
  require_route
  mkdir -p "$CI_ARTIFACT_DIR"
  test -n "${RUNNER_NAME:-}"
  test -n "${RUNNER_ARCH:-}"
  test "$DEVELOPER_DIR" = /Applications/Xcode_26.6.app/Contents/Developer
  test "${SIMULATOR_RUNTIME:-}:${SIMULATOR_RUNTIME_BUILD:-}:${SIMULATOR_NAME:-}" = 'iOS 26.2:23C54:iPhone 17'
  printf 'ImageOS=%s\nImageVersion=%s\nImageArch=%s\n' \
    "${ImageOS:-unknown}" "${ImageVersion:-unknown}" "${ImageArch:-unknown}" \
    | tee "$CI_ARTIFACT_DIR/runner-image.txt"
  printf 'provider=%s\nlabel=%s\nrunner_name=%s\nrunner_architecture=%s\nuname_architecture=%s\nmacos_product_version=%s\ndeveloper_dir=%s\n' \
    "$CI_RUNNER_PROVIDER" "$CI_RUNNER_LABEL" "$RUNNER_NAME" "$RUNNER_ARCH" \
    "$(uname -m)" "$(sw_vers -productVersion)" "$DEVELOPER_DIR" \
    | tee "$CI_ARTIFACT_DIR/runner-provider.txt"
  printf 'macos_product_name=%s\nmacos_build_version=%s\n' \
    "$(sw_vers -productName)" "$(sw_vers -buildVersion)" \
    | tee -a "$CI_ARTIFACT_DIR/runner-provider.txt"
  printf 'repository=%s\nref=%s\nsha=%s\nrun_id=%s\nrun_attempt=%s\n' \
    "$GITHUB_REPOSITORY" "$GITHUB_REF" "$GITHUB_SHA" "$GITHUB_RUN_ID" "$GITHUB_RUN_ATTEMPT" \
    | tee "$CI_ARTIFACT_DIR/github-run.txt"
  test -d "$DEVELOPER_DIR"
  test -f "$PROJECT_PATH/project.pbxproj"
  test -f "$PROJECT_PATH/xcshareddata/xcschemes/$SCHEME.xcscheme"
  test "$EXPECTED_MINIMUM_IOS" != "UNSET"
  xcodebuild -version | tee "$CI_ARTIFACT_DIR/xcode-version.txt"
  grep -Fxq "$EXPECTED_XCODE_VERSION" "$CI_ARTIFACT_DIR/xcode-version.txt"
  grep -Fxq "$EXPECTED_XCODE_BUILD" "$CI_ARTIFACT_DIR/xcode-version.txt"
  local sdk_version sdk_build
  sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
  sdk_build="$(xcrun --sdk iphonesimulator --show-sdk-build-version)"
  printf 'sdk=iphonesimulator\nversion=%s\nbuild=%s\n' "$sdk_version" "$sdk_build" \
    | tee "$CI_ARTIFACT_DIR/native-sdk.txt"
  test "$sdk_version:$sdk_build" = 26.5:23F81a
  xcodebuild -list -json -project "$PROJECT_PATH" | tee "$CI_ARTIFACT_DIR/xcode-list.json"
  jq -e --arg scheme "$SCHEME" '.project.schemes | index($scheme) != null' \
    "$CI_ARTIFACT_DIR/xcode-list.json" > /dev/null
  xcodebuild -showBuildSettings -project "$PROJECT_PATH" -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" | tee "$CI_ARTIFACT_DIR/build-settings.txt"
  local targets
  targets="$(awk -F'= ' '/^[[:space:]]*IPHONEOS_DEPLOYMENT_TARGET = / {print $2}' \
    "$CI_ARTIFACT_DIR/build-settings.txt" | LC_ALL=C sort -u)"
  test "$(printf '%s\n' "$targets" | sed '/^$/d' | wc -l | tr -d ' ')" -eq 1
  test "$targets" = "$EXPECTED_MINIMUM_IOS"

  # A fresh owned Simulator of the exact runtime; it is deleted after the checkpoint.
  xcrun simctl list runtimes -j > "$CI_ARTIFACT_DIR/simulator-runtimes.json"
  local runtime_id device_type_id udid state runtime_build
  runtime_id="$(jq -r --arg name "$SIMULATOR_RUNTIME" --arg build "$SIMULATOR_RUNTIME_BUILD" \
    '.runtimes[] | select(.name == $name and .isAvailable == true and .buildversion == $build) | .identifier' \
    "$CI_ARTIFACT_DIR/simulator-runtimes.json" | head -n 1)"
  test -n "$runtime_id"
  xcrun simctl list devicetypes -j > "$CI_ARTIFACT_DIR/simulator-device-types.json"
  device_type_id="$(jq -r --arg name "$SIMULATOR_NAME" '.devicetypes[] | select(.name == $name) | .identifier' \
    "$CI_ARTIFACT_DIR/simulator-device-types.json" | head -n 1)"
  test -n "$device_type_id"
  udid="$(xcrun simctl create "$SIMULATOR_NAME" "$device_type_id" "$runtime_id")"
  test -n "$udid"
  printf 'CI_NATIVE_CREATED_SIMULATOR_UDID=%s\n' "$udid" >> "$GITHUB_ENV"
  xcrun simctl list devices available -j > "$CI_ARTIFACT_DIR/simulator-devices.json"
  state="$(jq -er --arg runtime "$runtime_id" --arg udid "$udid" '
    [.devices[$runtime][] | select(.udid == $udid) | .state]
    | if length == 1 then .[0] else error("expected exactly one selected Simulator state") end
  ' "$CI_ARTIFACT_DIR/simulator-devices.json")"
  test "$state" = Shutdown
  runtime_build="$(jq -er --arg runtime "$runtime_id" '.runtimes[] | select(.identifier == $runtime) | .buildversion' \
    "$CI_ARTIFACT_DIR/simulator-runtimes.json")"
  test "$runtime_build" = "$SIMULATOR_RUNTIME_BUILD"
  printf 'runtime=%s\nruntime_build=%s\nname=%s\nudid=%s\ninitial_state=%s\n' \
    "$SIMULATOR_RUNTIME" "$runtime_build" "$SIMULATOR_NAME" "$udid" "$state" \
    | tee "$CI_ARTIFACT_DIR/simulator-selection.txt"
  printf 'CI_DESTINATION=platform=iOS Simulator,id=%s\nCI_SIMULATOR_UDID=%s\nCI_SIMULATOR_INITIAL_STATE=%s\n' \
    "$udid" "$udid" "$state" >> "$GITHUB_ENV"
}

# Verify setup budget before build.
setup_budget() {
  test -n "${CI_BUDGET_START_EPOCH:-}"
  test -n "${CI_SETUP_ARTIFACT_TIMEOUT_SECONDS:-}"
  local elapsed="$(( $(date +%s) - CI_BUDGET_START_EPOCH ))"
  printf 'setup_elapsed_seconds=%s\nsetup_budget_seconds=%s\n' "$elapsed" "$CI_SETUP_ARTIFACT_TIMEOUT_SECONDS" \
    | tee "$CI_ARTIFACT_DIR/setup-budget.txt"
  printf 'CI_SETUP_ELAPSED_SECONDS=%s\n' "$elapsed" >> "$GITHUB_ENV"
  test "$elapsed" -le "$CI_SETUP_ARTIFACT_TIMEOUT_SECONDS"
}

# Recheck setup budget after V23 shared payload restore.
restore_budget() {
  test "$V23_SHARED_ROLE" = consumer
  local elapsed="$(( $(date +%s) - CI_BUDGET_START_EPOCH ))"
  test "$elapsed" -ge 0
  test "$elapsed" -le "$CI_SETUP_ARTIFACT_TIMEOUT_SECONDS"
  printf 'shared_restore_setup_elapsed_seconds=%s\n' "$elapsed" > "$CI_ARTIFACT_DIR/v23-shared-restore-budget.txt"
  printf 'CI_SETUP_ELAPSED_SECONDS=%s\n' "$elapsed" >> "$GITHUB_ENV"
}

# Boot selected Simulator (a background step; its logs are required evidence).
boot() {
  test "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" = "900"
  test -n "${CI_SIMULATOR_UDID:-}"
  test "${CI_SIMULATOR_INITIAL_STATE:-}" = Shutdown
  local start end elapsed
  local -a status log_status
  start="$(date +%s)"
  case "${CI_BUDGET_START_EPOCH:?}" in *[!0-9]* | "") exit 1 ;; esac
  test "$start" -ge "$CI_BUDGET_START_EPOCH"
  printf 'start_epoch=%s\nudid=%s\ninitial_state=%s\naction=boot\nbudget_seconds=%s\ncommand=xcrun simctl bootstatus %s -b\n' \
    "$start" "$CI_SIMULATOR_UDID" "$CI_SIMULATOR_INITIAL_STATE" "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" \
    "$CI_SIMULATOR_UDID" | tee "$CI_ARTIFACT_DIR/simulator-boot-start.log"
  printf 'CI_SIMULATOR_BOOT_START_EPOCH=%s\n' "$start" >> "$GITHUB_ENV"
  set +e
  bash Scripts/run-with-timeout.sh "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" \
    xcrun simctl bootstatus "$CI_SIMULATOR_UDID" -b 2>&1 | tee "$CI_ARTIFACT_DIR/simulator-boot.log"
  status=( "${PIPESTATUS[@]}" )
  end="$(date +%s)"
  printf '\nend_epoch=%s\nbootstatus_exit=%s\ntee_exit=%s\n' "$end" "${status[0]}" "${status[1]:-}" \
    | tee -a "$CI_ARTIFACT_DIR/simulator-boot.log"
  log_status=( "${PIPESTATUS[@]}" )
  set -e
  test "${#status[@]}" -eq 2
  test "${status[0]}" -eq 0
  test "${status[1]}" -eq 0
  test "${log_status[0]}" -eq 0
  test "${log_status[1]}" -eq 0
  test "$end" -ge "$start"
  elapsed="$(( end - start ))"
  printf 'ready_epoch=%s\nready_udid=%s\nready_elapsed_seconds=%s\nbudget_seconds=%s\n' \
    "$end" "$CI_SIMULATOR_UDID" "$elapsed" "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS" \
    | tee -a "$CI_ARTIFACT_DIR/simulator-boot.log"
  test "$elapsed" -le "$CI_SIMULATOR_BOOT_TIMEOUT_SECONDS"
  printf 'CI_SIMULATOR_READY_UDID=%s\nCI_SIMULATOR_READY_EPOCH=%s\nCI_SIMULATOR_READY_ELAPSED_SECONDS=%s\n' \
    "$CI_SIMULATOR_UDID" "$end" "$elapsed" >> "$GITHUB_ENV"
}

# Remove owned isolated Simulator.
remove_simulator() {
  local udid="${CI_NATIVE_CREATED_SIMULATOR_UDID:-}"
  test -n "$udid"
  [[ "$udid" =~ ^[0-9A-Fa-f-]{36}$ ]]
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid"
  local inventory="$RUNNER_TEMP/v23-shared-simulator-after-delete.json"
  xcrun simctl list devices -j > "$inventory"
  jq -e --arg udid "$udid" 'all(.devices[][]?; .udid != $udid)' "$inventory" > /dev/null
  printf 'isolated=true\ndeleted=true\nudid=%s\n' "$udid" > "$CI_ARTIFACT_DIR/native-simulator-lifecycle.txt"
}

write_checksums() {
  local checksum_file="$RUNNER_TEMP/FieldEvidenceCI-checksums.txt"
  (
    cd "$CI_ARTIFACT_DIR"
    find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done
  ) > "$checksum_file"
  mv "$checksum_file" "$CI_ARTIFACT_DIR/SHA256SUMS.txt"
  (cd "$CI_ARTIFACT_DIR" && shasum -a 256 -c SHA256SUMS.txt)
}

# Hash collected evidence. A setup failure is retained without inventing timing.
hash_evidence() {
  mkdir -p "$CI_ARTIFACT_DIR"
  rm -f "$CI_ARTIFACT_DIR/SHA256SUMS.txt"
  if [ "${RUNTIME_SETUP_OUTCOME:-}" = failure ] && [ -z "${CI_SETUP_ELAPSED_SECONDS:-}" ] &&
     [ "${CI_TASK_ID:-}" = V23-INTEGRATION-20260910 ] &&
     [ "${CI_NATIVE_ACCEPTANCE_CONTRACT:-}" = v23.integration.current-native.v1 ] &&
     [ "${CI_RUNNER_PROVIDER:-}:${CI_RUNNER_LABEL:-}" = github:macos-26 ]; then
    printf 'setup_elapsed_seconds=unavailable\nsetup_artifact_elapsed_seconds=unavailable\nacceptance_eligible=false\nreason=setup-failed-before-accounting\n' \
      > "$CI_ARTIFACT_DIR/v23-setup-failure-evidence.txt"
    write_checksums
    exit 1
  fi
  test -n "${CI_ARTIFACT_START_EPOCH:-}"
  test -n "${CI_SETUP_ARTIFACT_TIMEOUT_SECONDS:-}"
  test -n "${CI_SETUP_ELAPSED_SECONDS:-}"
  local artifact_elapsed="$(( $(date +%s) - CI_ARTIFACT_START_EPOCH ))"
  local total="$(( CI_SETUP_ELAPSED_SECONDS + artifact_elapsed ))"
  printf 'setup_elapsed_seconds=%s\nartifact_elapsed_seconds=%s\nsetup_artifact_elapsed_seconds=%s\nsetup_artifact_budget_seconds=%s\n' \
    "$CI_SETUP_ELAPSED_SECONDS" "$artifact_elapsed" "$total" "$CI_SETUP_ARTIFACT_TIMEOUT_SECONDS" \
    > "$CI_ARTIFACT_DIR/artifact-budget.txt"
  write_checksums
  test "$total" -le "$CI_SETUP_ARTIFACT_TIMEOUT_SECONDS"
}

# Recheck evidence-finalization budget.
finalization_budget() {
  test -n "${CI_ARTIFACT_START_EPOCH:-}"
  test -n "${CI_SETUP_ARTIFACT_TIMEOUT_SECONDS:-}"
  test -n "${CI_SETUP_ELAPSED_SECONDS:-}"
  test "$(( CI_SETUP_ELAPSED_SECONDS + $(date +%s) - CI_ARTIFACT_START_EPOCH ))" -le "$CI_SETUP_ARTIFACT_TIMEOUT_SECONDS"
}

# Verify selected total budget before upload.
total_budget() {
  test -n "${CI_BUDGET_START_EPOCH:-}"
  test -n "${CI_TOTAL_BUDGET_SECONDS:-}"
  case "$CI_BUDGET_START_EPOCH:$CI_TOTAL_BUDGET_SECONDS" in *[!0-9:]*) exit 1 ;; esac
  local elapsed="$(( $(date +%s) - CI_BUDGET_START_EPOCH ))"
  printf 'elapsed_seconds=%s\ntotal_budget_seconds=%s\n' "$elapsed" "$CI_TOTAL_BUDGET_SECONDS"
  test "$elapsed" -le "$CI_TOTAL_BUDGET_SECONDS"
}

case "${1:-}" in
  admit) admit ;;
  toolchain) toolchain ;;
  setup-budget) setup_budget ;;
  restore-budget) restore_budget ;;
  boot) boot ;;
  remove-simulator) remove_simulator ;;
  hash) hash_evidence ;;
  finalization-budget) finalization_budget ;;
  total-budget) total_budget ;;
  *) printf 'usage: v23-shared-worker.sh admit|toolchain|setup-budget|restore-budget|boot|remove-simulator|hash|finalization-budget|total-budget\n' >&2; exit 64 ;;
esac
