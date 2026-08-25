#!/usr/bin/env bash
set -euo pipefail

source_root="${1:?segment source root required}"
output_root="${2:?assembled output root required}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
plan_path="$repo_root/Scripts/s10-4-segment-plan.json"
task_contract_path="$repo_root/docs/design/s10/s10-accessibility-common-tasks.json"
shard_id="s10.4.current.ax-text"
requirement_id="ax_text"
profile_id="iphone-17-ios-26.2-current"

test "${S10_4_SEGMENT_MATRIX_RESULT:-}" = "success"
test -f "$plan_path"
test -f "$task_contract_path"
test -d "$source_root"
test -d "$output_root"
test -z "$(find "$output_root" -mindepth 1 -print -quit)"

staging_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
test -d "$staging_parent"
staging_root="$(mktemp -d "$staging_parent/s10-4-assembled.XXXXXX")"
cleanup_on_error() {
  status=$?
  rm -rf "$staging_root"
  rm -f \
    "$output_root/s10-4/$shard_id/shard-receipt.json" \
    "$output_root/s10-4/$shard_id/segment-aggregation.json" \
    "$output_root/SHA256SUMS.txt" 2>/dev/null || true
  exit "$status"
}
trap cleanup_on_error ERR INT TERM

sha256_file() {
  shasum -a 256 "$1" | awk '{print toupper($1)}'
}

sha256_text() {
  printf '%s' "$1" | shasum -a 256 | awk '{print toupper($1)}'
}

directory_digest() {
  local source_dir="$1"
  local rows
  rows="$(mktemp)"
  : > "$rows"
  while IFS= read -r file_path; do
    printf '%s  %s\n' "$(sha256_file "$file_path")" "${file_path#"$source_dir/"}" >> "$rows"
  done < <(find "$source_dir" -type f | LC_ALL=C sort)
  sha256_file "$rows"
  rm -f "$rows"
}

plan_sha256="$(sha256_file "$plan_path")"
test "$(sha256_file "$repo_root/Scripts/ci-selection.json")" = "$(jq -r '.selectorSHA256' "$plan_path")"
test "$(sha256_file "$repo_root/Scripts/s10-4-shards.json")" = "$(jq -r '.shardContractSHA256' "$plan_path")"
test "$(sha256_file "$repo_root/docs/design/s10/s10-screen-state-inventory.json")" = "$(jq -r '.inventorySHA256' "$plan_path")"
test "$(sha256_file "$task_contract_path")" = "$(jq -r '.commonTaskSchemaSHA256' "$plan_path")"
kernel_json="$(jq -cS '{
  productHead,
  selectorSHA256,
  shardContractSHA256,
  inventorySHA256,
  commonTaskSchemaSHA256,
  orderedStateSHA256,
  stateSetSHA256,
  captureBaselineSHA256,
  state27CallerSHA256,
  preflightHelperSHA256,
  issueRecheckHelperSHA256,
  exceptionAuthorities
}' "$plan_path")"
evidence_kernel_sha256="$(sha256_text "$kernel_json")"
jq -e --arg kernel "$evidence_kernel_sha256" '
  .schemaVersion == 1
  and .shardID == "s10.4.current.ax-text"
  and .requirementID == "ax_text"
  and .deviceProfileID == "iphone-17-ios-26.2-current"
  and .runnerProvider == "github"
  and .runnerLabel == "macos-26"
  and .xcodeVersion == "Xcode 26.6"
  and .xcodeBuild == "17F113"
  and .sdkName == "iphonesimulator26.5"
  and .sdkBuild == "23F81a"
  and .simulatorName == "iPhone 17"
  and .simulatorRuntime == "iOS 26.2"
  and .simulatorRuntimeBuild == "23C54"
  and .crossSessionBuildReuse == false
  and .crossSessionTestWithoutBuilding == false
  and .evidenceKernelSHA256 == $kernel
  and (.orderedStateIDs | length) == 67
  and (.orderedStateIDs | unique | length) == 67
  and [.segments[].segmentID] == ["segment-1", "segment-2", "segment-3"]
  and [.segments[].stateCount] == [22, 28, 17]
  and [.segments[].replayCount] == [0, 22, 50]
  and .segments[0].ownedStateIDs == .orderedStateIDs[0:22]
  and .segments[1].ownedStateIDs == .orderedStateIDs[22:50]
  and .segments[2].ownedStateIDs == .orderedStateIDs[50:67]
  and .segments[0].replayStateIDs == []
  and .segments[1].replayStateIDs == .orderedStateIDs[0:22]
  and .segments[2].replayStateIDs == .orderedStateIDs[0:50]
  and (.exceptionAuthorities | length) == 8
  and ([.exceptionAuthorities[].exceptionIssueID] | unique | length) == 8
  and all(.exceptionAuthorities[];
    .shardID == "s10.4.current.ax-text"
    and (.stateID | startswith("state."))
    and (.taskID | type == "string" and length > 0)
    and .exceptionOwner == "palatis3"
    and (.exceptionExpiresAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")))
' "$plan_path" > /dev/null

mapfile -t source_dirs < <(find "$source_root" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)
test "${#source_dirs[@]}" -eq 3
test -z "$(find "$source_root" -mindepth 1 -maxdepth 1 ! -type d -print -quit)"

mkdir -p \
  "$staging_root/segment-sources" \
  "$staging_root/s10-4/$shard_id/candidates" \
  "$staging_root/ax/$shard_id" \
  "$staging_root/contrast/$shard_id" \
  "$staging_root/accessibility/$shard_id"
combined_shard="$staging_root/s10-4/$shard_id"
: > "$combined_shard/state-ax.ndjson"
: > "$combined_shard/contrast.ndjson"
: > "$combined_shard/accessibility.ndjson"
printf '[]\n' > "$combined_shard/candidate-files.json"
printf '[]\n' > "$combined_shard/source-segment-receipts.json"

declare -A seen_segments=()
declare -A seen_sessions=()
common_head=""
common_ref=""
common_run=""
common_attempt=""

for source_dir in "${source_dirs[@]}"; do
  test -f "$source_dir/SHA256SUMS.txt"
  test -z "$(find "$source_dir" -type l -print -quit)"
  (cd "$source_dir" && shasum -a 256 -c SHA256SUMS.txt)
  receipt="$source_dir/s10-4/$shard_id/segment-receipt.json"
  test -s "$receipt"
  segment_id="$(jq -er '.segmentID' "$receipt")"
  case "$segment_id" in segment-1|segment-2|segment-3) ;; *) exit 1 ;; esac
  test -z "${seen_segments[$segment_id]+x}"
  seen_segments[$segment_id]=1
  segment_json="$(jq -cer --arg id "$segment_id" '.segments[] | select(.segmentID == $id)' "$plan_path")"
  state_count="$(jq -r '.stateCount' <<< "$segment_json")"
  replay_count="$(jq -r '.replayCount' <<< "$segment_json")"

  jq -e \
    --arg segment "$segment_id" \
    --arg plan "$plan_sha256" \
    --arg kernel "$evidence_kernel_sha256" \
    --arg shard "$shard_id" \
    --arg requirement "$requirement_id" \
    --arg profile "$profile_id" \
    --argjson expected "$segment_json" '
      .schemaVersion == 1
      and .receiptKind == "s10.4-segment"
      and .complete == true
      and .finalAcceptanceEligible == false
      and .segmentID == $segment
      and .shardID == $shard
      and .requirementID == $requirement
      and .deviceProfileID == $profile
      and .segmentPlanSHA256 == $plan
      and .evidenceKernelSHA256 == $kernel
      and .selectorSHA256 == "571AC854A230A95F90368EC50CA625AD13B170AFC06DFF503D1C9F99796EF7D5"
      and .shardContractSHA256 == "C023ADE99CAB0F9ED2984C90BCC0E03B0D05A05643DF7185201CC00772E3C8E4"
      and .inventorySHA256 == "6C820E8A1160297F561EABF1873BE82403589B408E4A8FA3318269293242F507"
      and .commonTaskSchemaSHA256 == "B7EDB1DD18BAB6DEE1884DA52C15F63AD5AD06045F58444C61442957558999F0"
      and .runnerProvider == "github"
      and .runnerLabel == "macos-26"
      and .xcodeVersion == "Xcode 26.6"
      and .xcodeBuild == "17F113"
      and .sdkName == "iphonesimulator26.5"
      and .sdkBuild == "23F81a"
      and .simulatorRuntime == "iOS 26.2"
      and .simulatorRuntimeBuild == "23C54"
      and .simulatorName == "iPhone 17"
      and .buildMode == "independent-build-for-testing"
      and .crossSessionBuildReuse == false
      and .crossSessionTestWithoutBuilding == false
      and .ordinal == $expected.ordinal
      and .startOrdinal == $expected.startOrdinal
      and .endOrdinal == $expected.endOrdinal
      and .stateCount == $expected.stateCount
      and .replayCount == $expected.replayCount
      and .ownedStateIDs == $expected.ownedStateIDs
      and .replayStateIDs == $expected.replayStateIDs
      and .ownedStateSHA256 == $expected.ownedStateSHA256
      and .replayStateSHA256 == $expected.replayStateSHA256
      and .markerCount == $expected.stateCount
      and .replayRowCount == $expected.replayCount
      and .diagnosticCount == 0
      and .attachmentCount == ($expected.stateCount + 1)
      and .segmentTerminalAttachmentCount == 1
      and .candidateCount == $expected.stateCount
      and .stateAXRowCount == $expected.stateCount
      and .contrastRowCount == $expected.stateCount
      and .accessibilityRowCount == 0
      and ((.unitTestSelectors | type) == "array")
      and ((.unitTestSelectors | length) == 5)
      and ((.unitTestSelectors | unique | length) == 5)
      and .unitTestSelectors == [
        "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests/testFrozenBrandPaletteProvidesExactOpaqueNormalAndIncreasedContrastTruth",
        "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests/testFrozenInventoryDerivesExactUnpromotedVisualAndAccessibilityMatrices",
        "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests/testMigratedProductAndTokenCoverageRemainBoundToFrozenInventory",
        "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests/testMinimumOSCameraDeniedLegacyTabCorrectionIsNarrowAndDiagnosticFree",
        "FieldEvidenceAppTests/S10_4AutomatedBrandLabTests/testPinnedOverlaySelectorAndExactSevenPlusSevenShardContract"
      ]
      and ((.uiTestSelectors | type) == "array")
      and ((.uiTestSelectors | length) == 1)
      and .uiTestSelectors == [
        "FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests/testAutomatedBrandLabShard"
      ]
      and .unitExecutedTestCount == 5
      and .uiExecutedTestCount == 1
      and (.buildIdentitySHA256 | test("^[0-9A-F]{64}$"))
      and (.unitIdentitySHA256 | test("^[0-9A-F]{64}$"))
      and (.uiIdentitySHA256 | test("^[0-9A-F]{64}$"))
      and (.sessionIdentitySHA256 | test("^[0-9A-F]{64}$"))
    ' "$receipt" > /dev/null

  for bundle in Build.xcresult UnitTests.xcresult UISmoke.xcresult; do
    test -d "$source_dir/$bundle"
    test -n "$(find "$source_dir/$bundle" -mindepth 1 -print -quit)"
  done
  test -s "$source_dir/build-smoke.log"
  test -s "$source_dir/test-smoke.log"
  test -s "$source_dir/ui-smoke.log"
  test "$(grep -Fxc '** TEST BUILD SUCCEEDED **' "$source_dir/build-smoke.log" || true)" -eq 1
  test "$(grep -Fxc '** TEST EXECUTE SUCCEEDED **' "$source_dir/test-smoke.log" || true)" -eq 1
  test "$(grep -Fxc '** TEST EXECUTE SUCCEEDED **' "$source_dir/ui-smoke.log" || true)" -eq 1
  test "$(directory_digest "$source_dir/Build.xcresult")" = "$(jq -r '.buildIdentitySHA256' "$receipt")"
  test "$(directory_digest "$source_dir/UnitTests.xcresult")" = "$(jq -r '.unitIdentitySHA256' "$receipt")"
  test "$(directory_digest "$source_dir/UISmoke.xcresult")" = "$(jq -r '.uiIdentitySHA256' "$receipt")"

  head="$(jq -er '.productHead' "$receipt")"
  ref="$(jq -er '.ref' "$receipt")"
  run="$(jq -er '.runID' "$receipt")"
  attempt="$(jq -er '.runAttempt' "$receipt")"
  test "$(jq -er '.artifactName' "$receipt")" = \
    "ios-ci-$run-$attempt-$shard_id-$segment_id"
  test "$(basename "$source_dir")" = "$(jq -er '.artifactName' "$receipt")"
  runner_name="$(jq -er '.runnerName' "$receipt")"
  simulator_udid="$(jq -er '.simulatorUDID' "$receipt")"
  job_id="$(jq -er '.jobID' "$receipt")"
  test -n "$runner_name"
  test -n "$job_id"
  test "$(tr '[:lower:]' '[:upper:]' <<< "$simulator_udid")" = "$simulator_udid"
  test "$(grep -Ec '^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$' \
    <<< "$simulator_udid")" -eq 1
  if test -z "$common_head"; then
    common_head="$head"; common_ref="$ref"; common_run="$run"; common_attempt="$attempt"
  else
    test "$head" = "$common_head"
    test "$ref" = "$common_ref"
    test "$run" = "$common_run"
    test "$attempt" = "$common_attempt"
  fi
  test "$head" = "${GITHUB_SHA:?}"
  test "$ref" = "${GITHUB_REF:?}"
  test "$run" = "${GITHUB_RUN_ID:?}"
  test "$attempt" = "${GITHUB_RUN_ATTEMPT:?}"
  session="$(jq -er '.sessionIdentitySHA256' "$receipt")"
  expected_session="$(printf '%s\n%s\n%s\n%s\n' \
    "$runner_name" "$simulator_udid" "$job_id" "$(jq -er '.uiIdentitySHA256' "$receipt")" \
    | shasum -a 256 | awk '{print toupper($1)}')"
  test "$session" = "$expected_session"
  test -z "${seen_sessions[$session]+x}"
  seen_sessions[$session]=1

  shard_source="$source_dir/s10-4/$shard_id"
  test ! -e "$shard_source/shard-receipt.json"
  test ! -e "$source_dir/accessibility/$shard_id"
  test "$(jq 'length' "$shard_source/state-ax.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/contrast.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/candidate-exports.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/candidate-files.json")" -eq "$state_count"
  test "$(jq 'length' "$shard_source/replay-rows.json")" -eq "$replay_count"
  jq -e --arg shard "$shard_id" --arg segment "$segment_id" --argjson expected "$segment_json" '
    [.[].stateID] == $expected.replayStateIDs
    and [.[].ordinal] == (if $expected.replayCount == 0 then [] else [range(1; $expected.replayCount + 1)] end)
    and all(.[]; .shardID == $shard and .segmentID == $segment)
  ' "$shard_source/replay-rows.json" > /dev/null
  jq -e --argjson expected "$segment_json" '[.[].stateID] == $expected.ownedStateIDs' "$shard_source/state-ax.json" > /dev/null
  jq -e --argjson expected "$segment_json" '[.[].stateID] == $expected.ownedStateIDs' "$shard_source/contrast.json" > /dev/null
  jq -e --argjson expected "$segment_json" '
    [.[].stateID] == $expected.ownedStateIDs
    and all(.[];
      (.exportedFileName | type == "string")
      and (.exportedFileName | test("^[A-Za-z0-9._-]+$")))
  ' "$shard_source/candidate-exports.json" > /dev/null
  jq -e --argjson expected "$segment_json" '
    . as $candidateRows
    | ([$candidateRows[].stateID] == $expected.ownedStateIDs)
      and all(range(0; ($candidateRows | length));
        . as $index
        | $candidateRows[$index].artifactPath
            == ("candidates/" + $expected.ownedStateIDs[$index] + ".png")
          and ($candidateRows[$index].sha256 | test("^[0-9A-F]{64}$"))
          and ($candidateRows[$index].bytes | type == "number" and . > 0))
  ' "$shard_source/candidate-files.json" > /dev/null
  test "$(find "$shard_source/candidates" -type f -name 'state.*.png' | wc -l | tr -d ' ')" -eq "$state_count"
  mapfile -t observed_markers < <(sed -n 's/^S10_MIGRATION_STATE state=//p' "$source_dir/ui-smoke.log")
  test "${#observed_markers[@]}" -eq "$state_count"
  test "$(printf '%s\n' "${observed_markers[@]}" | jq -Rsc 'split("\n") | map(select(length>0))')" = \
    "$(jq -c '.ownedStateIDs' <<< "$segment_json")"
  mapfile -t observed_replays < <(sed -n 's/^S10_4_SEGMENT_REPLAY //p' "$source_dir/ui-smoke.log")
  test "${#observed_replays[@]}" -eq "$replay_count"
  test "$(grep -Ec '^S10_4_AX ' "$source_dir/ui-smoke.log" || true)" -eq 0
  test "$(grep -Ec '^S10_4_FRONTIER_REPLAY ' "$source_dir/ui-smoke.log" || true)" -eq 0
  test "$(grep -Ec '^S10_4_.*DIAGNOSTIC' "$source_dir/ui-smoke.log" || true)" -eq 0
  test "$(grep -Eic 'Lost connection to testmanagerd|XCTHTestOperationCoordinatorErrorDomain' "$source_dir/ui-smoke.log" || true)" -eq 0
  jq -e '[.[]?.attachments[]? | select(
    .suggestedHumanReadableName == "UI Snapshot"
    or .suggestedHumanReadableName == "Synthesized Event"
    or .suggestedHumanReadableName == "Screen Recording"
    or ((.suggestedHumanReadableName // "") | test("diagnostic"; "i"))
    or .isAssociatedWithFailure == true)] | length == 0' \
    "$shard_source/xcresult-attachment-manifest.json" > /dev/null
  jq -e --arg name "S10.4 segment terminal $segment_id $shard_id" \
    --argjson stateCount "$state_count" '
      ([.[]?.attachments[]?] | length) == ($stateCount + 1)
      and ([.[]?.attachments[]? | select(
        .isAssociatedWithFailure == false
        and (.suggestedHumanReadableName | type == "string")
        and ((.suggestedHumanReadableName
          | sub("_0_[0-9A-Fa-f-]{36}\\."; ".")) == $name)
        and (.exportedFileName | type == "string")
        and (.exportedFileName | test("^[A-Za-z0-9._-]+$"))
      )] | length) == 1
    ' "$shard_source/xcresult-attachment-manifest.json" > /dev/null

  while IFS= read -r candidate_row; do
    state_id="$(jq -er '.stateID' <<< "$candidate_row")"
    candidate_file="$shard_source/candidates/$state_id.png"
    test -f "$candidate_file"
    test "$(sha256_file "$candidate_file")" = "$(jq -er '.sha256' <<< "$candidate_row")"
    test "$(wc -c < "$candidate_file" | tr -d ' ')" = "$(jq -er '.bytes' <<< "$candidate_row")"
  done < <(jq -c '.[]' "$shard_source/candidate-files.json")

  cp -a "$source_dir" "$staging_root/segment-sources/$segment_id"
  while IFS= read -r state_id; do
    test ! -e "$combined_shard/candidates/$state_id.png"
    test ! -e "$staging_root/ax/$shard_id/$state_id.json"
    test ! -e "$staging_root/contrast/$shard_id/$state_id.json"
    cp "$shard_source/candidates/$state_id.png" "$combined_shard/candidates/$state_id.png"
    cp "$source_dir/ax/$shard_id/$state_id.json" "$staging_root/ax/$shard_id/$state_id.json"
    cp "$source_dir/contrast/$shard_id/$state_id.json" "$staging_root/contrast/$shard_id/$state_id.json"
  done < <(jq -r '.ownedStateIDs[]' <<< "$segment_json")
  jq -c '.[]' "$shard_source/state-ax.json" >> "$combined_shard/state-ax.ndjson"
  jq -c '.[]' "$shard_source/contrast.json" >> "$combined_shard/contrast.ndjson"
  jq -s '.[0] + .[1]' "$combined_shard/candidate-files.json" "$shard_source/candidate-files.json" \
    > "$combined_shard/candidate-files.next.json"
  mv "$combined_shard/candidate-files.next.json" "$combined_shard/candidate-files.json"
  jq -s '.[0] + [.[1]]' "$combined_shard/source-segment-receipts.json" "$receipt" \
    > "$combined_shard/source-segment-receipts.next.json"
  mv "$combined_shard/source-segment-receipts.next.json" "$combined_shard/source-segment-receipts.json"
done

test "${#seen_segments[@]}" -eq 3
test "${#seen_sessions[@]}" -eq 3
jq -s '.' "$combined_shard/state-ax.ndjson" > "$combined_shard/state-ax.json"
jq -s '.' "$combined_shard/contrast.ndjson" > "$combined_shard/contrast.json"
jq -e --slurpfile plan "$plan_path" '[.[].stateID] == $plan[0].orderedStateIDs and length == 67' "$combined_shard/state-ax.json" > /dev/null
jq -e --slurpfile plan "$plan_path" '[.[].stateID] == $plan[0].orderedStateIDs and length == 67' "$combined_shard/contrast.json" > /dev/null
jq -e --slurpfile plan "$plan_path" '[.[].stateID] == $plan[0].orderedStateIDs and length == 67' "$combined_shard/candidate-files.json" > /dev/null
jq -e --arg shard "$shard_id" --arg requirement "$requirement_id" --arg profile "$profile_id" '
  all(.[];
    .shardID == $shard
    and .requirementID == $requirement
    and .deviceProfileID == $profile
    and .result == "PASS"
    and .evidenceID == ("s10.4-ax-" + $shard + "-" + .stateID)
    and .capture == "XCUIApplication.debugDescription"
    and (.axTreeSHA256 | test("^[0-9A-F]{64}$")))
' "$combined_shard/state-ax.json" > /dev/null
jq -e --arg shard "$shard_id" --arg requirement "$requirement_id" --arg profile "$profile_id" '
  all(.[];
    .shardID == $shard
    and .requirementID == $requirement
    and .deviceProfileID == $profile
    and (.result == "PASS" or .result == "EXCEPTION")
    and .evidenceID == ("s10.4-contrast-" + $shard + "-" + .stateID)
    and .audit == "XCUIAccessibilityAuditType.contrast"
    and (.axTreeSHA256 | test("^[0-9A-F]{64}$")))
' "$combined_shard/contrast.json" > /dev/null
test "$(find "$combined_shard/candidates" -type f -name 'state.*.png' | wc -l | tr -d ' ')" -eq 67
test "$(find "$staging_root/ax/$shard_id" -type f -name 'state.*.json' | wc -l | tr -d ' ')" -eq 67
test "$(find "$staging_root/contrast/$shard_id" -type f -name 'state.*.json' | wc -l | tr -d ' ')" -eq 67

# Every planned AX-text exception must be observed once under its exact state,
# owner, expiry, issue ID order, and public callback cardinality.
jq -e --arg today "$(date -u +%F)" --slurpfile plan "$plan_path" '
  def groups($authorities):
    $authorities | sort_by(.stateID, .exceptionIssueID) | group_by(.stateID)
    | map({
        stateID: .[0].stateID,
        issueIDs: map(.exceptionIssueID),
        owner: .[0].exceptionOwner,
        expiry: .[0].exceptionExpiresAt
      });
  ($plan[0].exceptionAuthorities) as $authorities
  | groups($authorities) as $expected
  | ([.[] | select(.result == "EXCEPTION")] | sort_by(.stateID)) as $actual
  | all(.[];
      if .result == "PASS" then
        .exceptionIssueID == ""
        and .exceptionOwner == ""
        and .exceptionExpiresAt == ""
        and .exceptionRationale == ""
        and .ignoredAuditIssues == []
      else .result == "EXCEPTION" end)
  and [$actual[].stateID] == [$expected[].stateID]
  and ($authorities | length) == 8
  and ($expected | length) == 6
  and all($actual[] as $row;
    ($expected[] | select(.stateID == $row.stateID)) as $group
    | $row.exceptionIssueID == ($group.issueIDs | join(" | "))
    and $row.exceptionOwner == $group.owner
    and $row.exceptionExpiresAt == $group.expiry
    and $today <= $row.exceptionExpiresAt
    and ($row.exceptionRationale | type == "string" and length > 0)
    and ($row.ignoredAuditIssues | type == "array" and length == ($group.issueIDs | length))
    and all($row.ignoredAuditIssues[];
      .auditTypeRawValue == "1"
      and .compactDescription == "Contrast failed"
      and .detailedDescription == "Contrast failed for SwiftUI.AccessibilityNode"
      and (.elementType == "XCUIElementType(rawValue: 48)")
      and (.elementFrame | type == "object")
      and .applicationFrame == {x:0,y:0,width:402,height:874}))
' "$combined_shard/contrast.json" > /dev/null

# Derive the same six canonical common-task rows from the verified state union.
mapfile -t task_ids < <(jq -r '.tasks[].task_id' "$task_contract_path")
test "${#task_ids[@]}" -eq 6
for task_id in "${task_ids[@]}"; do
  mapfile -t task_states < <(jq -r --arg task "$task_id" '.tasks[] | select(.task_id == $task) | .screen_state_ids | sort[]' "$task_contract_path")
  test "${#task_states[@]}" -gt 0
  state_evidence="[]"
  canonical_lines=()
  for state_id in "${task_states[@]}"; do
    digest="$(jq -er --arg state "$state_id" '.[] | select(.stateID == $state) | .axTreeSHA256' "$combined_shard/state-ax.json")"
    [[ "$digest" =~ ^[0-9A-F]{64}$ ]]
    state_evidence="$(jq -c --arg state "$state_id" --arg digest "$digest" '. + [{stateID:$state,axTreeSHA256:$digest}]' <<< "$state_evidence")"
    canonical_lines+=("$state_id|$digest")
  done
  canonical_evidence="$(IFS=$'\n'; printf '%s' "${canonical_lines[*]}")"
  state_set_text="$(IFS=$'\n'; printf '%s' "${task_states[*]}")"
  aggregate_digest="$(sha256_text "$canonical_evidence")"
  state_set_digest="$(sha256_text "$state_set_text")"
  task_authorities="$(jq -c --arg task "$task_id" '[.exceptionAuthorities[] | select(.taskID == $task)] | sort_by(.stateID,.exceptionIssueID)' "$plan_path")"
  exception_state_ids="$(jq -c '[.[].stateID] | unique | sort' <<< "$task_authorities")"
  issue_ids="$(jq -r '[.[].exceptionIssueID] | join(" | ")' <<< "$task_authorities")"
  owner="$(jq -r 'if length == 0 then "" else .[0].exceptionOwner end' <<< "$task_authorities")"
  expiry="$(jq -r 'if length == 0 then "" else .[0].exceptionExpiresAt end' <<< "$task_authorities")"
  exception_rationale=""
  if test "$(jq 'length' <<< "$task_authorities")" -gt 0; then
    exception_rationale="$(jq -r --argjson states "$exception_state_ids" \
      '[.[] | select(.stateID | IN($states[]))] | sort_by(.stateID) | map(.exceptionRationale) | join(" | ")' \
      "$combined_shard/contrast.json")"
    test -n "$exception_rationale"
  fi
  status="PASS"
  rationale="All task states produced AX-tree, focus-order, target-size, and strict Apple contrast evidence."
  if test -n "$issue_ids"; then
    status="EXCEPTION"
    if test "$(jq 'length' <<< "$task_authorities")" -eq 1; then
      rationale="All task states produced AX-tree, focus-order, and target-size evidence; the sole Apple contrast issue is bound to the named, expiring exception."
    else
      rationale="All task states produced AX-tree, focus-order, and target-size evidence; the exact Apple contrast issues are bound to the named, expiring exceptions."
    fi
  fi
  automated_ids="$(jq -cn --arg shard "$shard_id" --arg task "$task_id" --argjson states "$exception_state_ids" '[
      "s10.4-ax-"+$shard+"-"+$task,
      "s10.4-focus-order-"+$shard+"-"+$task,
      "s10.4-target-size-"+$shard+"-"+$task,
      "s10.4-contrast-"+$shard+"-"+$task
    ] + [$states[] | "s10.4-contrast-"+$shard+"-"+.]')"
  raw_task_file="$staging_root/.s10-4-$task_id.raw.json"
  jq -cnS \
    --arg taskID "$task_id" --arg shardID "$shard_id" --arg profile "$profile_id" \
    --arg status "$status" --arg issueIDs "$issue_ids" --arg owner "$owner" --arg expiry "$expiry" \
    --arg exceptionRationale "$exception_rationale" --arg rationale "$rationale" \
    --arg aggregate "$aggregate_digest" --arg stateSet "$state_set_digest" \
    --argjson evidence "$state_evidence" --argjson stateIDs "$exception_state_ids" \
    --argjson automatedIDs "$automated_ids" '
      {
        taskID:$taskID, shardID:$shardID, deviceProfileID:$profile, feature:"larger_text",
        automatedStatus:$status,
        automatedReviewer:"FieldEvidenceAppUITests/S10_4AutomatedBrandLabUITests",
        exceptionIssueID:$issueIDs, exceptionOwner:$owner, exceptionExpiresAt:$expiry,
        exceptionRationale:$exceptionRationale, exceptionStateIDs:$stateIDs,
        rationale:$rationale,
        evidenceID:("s10.4-ax-"+$shardID+"-"+$taskID),
        focusOrderEvidenceID:("s10.4-focus-order-"+$shardID+"-"+$taskID),
        targetSizeEvidenceID:("s10.4-target-size-"+$shardID+"-"+$taskID),
        contrastEvidenceID:("s10.4-contrast-"+$shardID+"-"+$taskID),
        automatedEvidenceIDs:$automatedIDs,
        stateCount:($evidence|length), stateSetSHA256:$stateSet,
        aggregateAXTreeSHA256:$aggregate, stateAXTreeDigests:$evidence
      }' > "$raw_task_file"
  jq -c '.' "$raw_task_file" >> "$combined_shard/accessibility.ndjson"
  jq -cS --arg productHead "$common_head" '. + {sourceProductHead:$productHead}' \
    "$raw_task_file" > "$staging_root/accessibility/$shard_id/$task_id.json"
  rm -f "$raw_task_file"
done
jq -s '.' "$combined_shard/accessibility.ndjson" > "$combined_shard/accessibility.json"
test "$(jq 'length' "$combined_shard/accessibility.json")" -eq 6
test "$(find "$staging_root/accessibility/$shard_id" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 6
for task_file in "$staging_root/accessibility/$shard_id"/*.json; do
  jq -e --arg shard "$shard_id" --arg head "$common_head" '
    .shardID == $shard
    and .sourceProductHead == $head
    and .evidenceID == ("s10.4-ax-" + $shard + "-" + .taskID)
    and .focusOrderEvidenceID == ("s10.4-focus-order-" + $shard + "-" + .taskID)
    and .targetSizeEvidenceID == ("s10.4-target-size-" + $shard + "-" + .taskID)
    and .contrastEvidenceID == ("s10.4-contrast-" + $shard + "-" + .taskID)
  ' "$task_file" > /dev/null
done

jq -n \
  --arg taskID "S10.4" --arg shardID "$shard_id" --arg requirementID "$requirement_id" \
  --arg deviceProfileID "$profile_id" --arg runtime "iOS 26.2" --arg runtimeBuild "23C54" \
  --arg simulatorName "iPhone 17" --arg productHead "$common_head" \
  '{schemaVersion:1,taskID:$taskID,shardID:$shardID,requirementID:$requirementID,
    deviceProfileID:$deviceProfileID,runtime:$runtime,runtimeBuild:$runtimeBuild,
    simulatorName:$simulatorName,productHead:$productHead,candidateCount:67,
    stateAXRowCount:67,accessibilityRowCount:6,contrastRowCount:67}' \
  > "$combined_shard/shard-receipt.json"

jq -n \
  --arg shardID "$shard_id" --arg requirementID "$requirement_id" --arg profile "$profile_id" \
  --arg head "$common_head" --arg ref "$common_ref" --arg run "$common_run" --arg attempt "$common_attempt" \
  --arg planSHA256 "$plan_sha256" --arg evidenceKernelSHA256 "$evidence_kernel_sha256" \
  --slurpfile receipts "$combined_shard/source-segment-receipts.json" '
    {schemaVersion:1,receiptKind:"s10.4-segment-aggregation",complete:true,
      finalAcceptanceEligible:true,shardID:$shardID,requirementID:$requirementID,
      deviceProfileID:$profile,productHead:$head,ref:$ref,runID:$run,runAttempt:$attempt,
      segmentPlanSHA256:$planSHA256,evidenceKernelSHA256:$evidenceKernelSHA256,
      segmentIDs:["segment-1","segment-2","segment-3"],segmentCount:3,
      distinctSessionCount:3,candidateCount:67,stateAXRowCount:67,
      contrastRowCount:67,accessibilityRowCount:6,sourceSegmentReceipts:$receipts[0]}' \
  > "$combined_shard/segment-aggregation.json"

cp "$plan_path" "$combined_shard/s10-4-segment-plan.json"
checksum_file="$staging_root/SHA256SUMS.txt.pending"
(
  cd "$staging_root"
  find . -type f ! -name 'SHA256SUMS.txt*' -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' file_path; do
        printf '%s  %s\n' "$(shasum -a 256 "$file_path" | awk '{print toupper($1)}')" "${file_path#./}"
      done
) > "$checksum_file"
mv "$checksum_file" "$staging_root/SHA256SUMS.txt"
(cd "$staging_root" && shasum -a 256 -c SHA256SUMS.txt)

cp -a "$staging_root/." "$output_root/"
rm -rf "$staging_root"
test -s "$output_root/SHA256SUMS.txt"
test -s "$output_root/s10-4/$shard_id/shard-receipt.json"
test -s "$output_root/s10-4/$shard_id/segment-aggregation.json"
trap - ERR INT TERM
