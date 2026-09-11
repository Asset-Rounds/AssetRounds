set -euo pipefail

require_nonempty_directory() {
  test -d "$1"
  test -n "$(find "$1" -mindepth 1 -print -quit)"
}

verify_executed_selectors() {
  local result_bundle="$1"
  local selectors_key="$2"
  local bundle_type="$3"
  local output_stem="$4"
  local test_results="$CI_ARTIFACT_DIR/${output_stem}-test-results.json"
  local executed_tests="$CI_ARTIFACT_DIR/${output_stem}-executed-tests.json"

  xcrun xcresulttool get test-results tests \
    --path "$result_bundle" --compact > "$test_results"
  test -s "$test_results"

  jq --arg bundleType "$bundle_type" '
    def normalize_identifier:
      sub("\\(\\)$"; "");
    def executed_cases($bundleName; $bundleType):
      . as $node
      | (
          if $node.nodeType? == $bundleType
          then ($node.name? // "")
          else $bundleName
          end
        ) as $nextBundle
      | if (
          $node.nodeType? == "Test Case"
          and ($nextBundle | type == "string" and length > 0)
          and ($node.nodeIdentifier? | type == "string" and length > 0)
          and (
            ($node.result? == "Passed")
            or ($node.result? == "Failed")
            or ($node.result? == "Expected Failure")
          )
        )
        then
          ($node.nodeIdentifier | normalize_identifier) as $identifier
          | {
              identifier: (
                if ($identifier | startswith($nextBundle + "/"))
                then $identifier
                else ($nextBundle + "/" + $identifier)
                end
              ),
              result: $node.result
            }
        else
          ($node.children[]? | executed_cases($nextBundle; $bundleType))
        end;
    [
      .testNodes[]?
      | executed_cases(null; $bundleType)
    ]
    | sort_by(.identifier)
    | unique_by(.identifier)
  ' "$test_results" > "$executed_tests"
  test -s "$executed_tests"

  jq -e --arg key "$selectors_key" --slurpfile executed "$executed_tests" '
    def normalize_identifier:
      sub("\\(\\)$"; "");
    .[$key] as $selectors
    | ($executed[0] // []) as $actual
    | (($actual | type) == "array" and ($actual | length) > 0)
      and all(
        $selectors[];
        . as $selector
        | ($selector | normalize_identifier) as $wanted
        | any(
            $actual[];
            (.identifier | normalize_identifier) as $observed
            | ($observed == $wanted)
              or ($observed | startswith($wanted + "/"))
          )
      )
  ' Scripts/ci-selection.json > /dev/null
}

test -s "$CI_ARTIFACT_DIR/simulator-boot-start.log"
test -s "$CI_ARTIFACT_DIR/simulator-boot.log"
test -s "$CI_ARTIFACT_DIR/runner-provider.txt"
if test "$CI_S10_4_SHARED_BUILD_MODE" = consumer; then
  test ! -e "$CI_ARTIFACT_DIR/Build.xcresult"
  test ! -e "$CI_ARTIFACT_DIR/UnitTests.xcresult"
  test ! -e "$CI_ARTIFACT_DIR/build-smoke.log"
  test ! -e "$CI_ARTIFACT_DIR/test-smoke.log"
  jq -e '.recordType == "consumer-build-reference" and .unitTestCount == 0 and .producerUnitTestCount == 5 and .productsUnchanged == true and .diagnosticOnly == false' \
    "$CI_ARTIFACT_DIR/shared-consumer/consumer-build-reference.json" > /dev/null
  test -s "$CI_ARTIFACT_DIR/shared-producer/unit-proof/producer-qualification.json"
else
  test -s "$CI_ARTIFACT_DIR/build-smoke.log"
  test -s "$CI_ARTIFACT_DIR/test-smoke.log"
  require_nonempty_directory "$CI_ARTIFACT_DIR/Build.xcresult"
  require_nonempty_directory "$CI_ARTIFACT_DIR/UnitTests.xcresult"
  verify_executed_selectors \
    "$CI_ARTIFACT_DIR/UnitTests.xcresult" \
    unitTestSelectors "Unit test bundle" unit
fi

if test "${CI_RUN_UI_SMOKE:-}" = "true"; then
  test -s "$CI_ARTIFACT_DIR/ui-smoke.log"
  require_nonempty_directory "$CI_ARTIFACT_DIR/UISmoke.xcresult"
  test -s "$CI_ARTIFACT_DIR/ui-final.png"
  if test "$CI_S10_4_SHARED_BUILD_MODE" = consumer; then
    jq -e '.validated == true and .nativeUIResult == "Passed" and .executedUITestCount == 1' \
      "$CI_ARTIFACT_DIR/s10-4-shared-native-validation.json" > /dev/null
  else
    verify_executed_selectors \
      "$CI_ARTIFACT_DIR/UISmoke.xcresult" \
      uiTestSelectors "UI test bundle" ui
  fi
  if test "${CI_TASK_ID:-}" = "S10.4"; then
    if test "$WORKER_S10_4_MINIMUM_CORE_SMOKE_ID" = s10.4.minimum-core-smoke.v1; then
      jq -e '.recordType == "minimum-core-smoke-proof" and .smokeComplete == true and .checkpointCount == 6 and .fullMatrixEligible == false and .fullShardComplete == false and .fullSegmentComplete == false' "$CI_ARTIFACT_DIR/s10-4-minimum-core-smoke-proof.json" > /dev/null
      test ! -e "$CI_ARTIFACT_DIR/s10-4/$CI_S10_4_SHARD_ID/shard-receipt.json"
      exit 0
    fi
    if test "$CI_S10_4_SHARED_BUILD_MODE" = consumer && { test "$CI_S10_4_SEGMENT_ID" != none || test "$WORKER_S10_4_MINIMUM_SEGMENT_ID" != none; }; then
      test -s "$CI_ARTIFACT_DIR/s10-4-shared-segment-validation.json"
      jq -e '.validated == true and .nativeUIResult == "Passed"' "$CI_ARTIFACT_DIR/s10-4-shared-segment-validation.json" > /dev/null
      exit 0
    fi
    test -s "$CI_ARTIFACT_DIR/simulator-runtime-policy.txt"
    test "${CI_S10_4_SHARD_ID:-none}" != "none"
    shard_evidence_path="$CI_ARTIFACT_DIR/s10-4/$CI_S10_4_SHARD_ID"
    if test "${CI_S10_4_SEGMENT_ID:-none}" != "none"; then
      segment_json="$(jq -cer --arg segment "$CI_S10_4_SEGMENT_ID" \
        '.segments[] | select(.segmentID == $segment)' \
        Scripts/s10-4-segment-plan.json)"
      expected_state_count="$(jq -r '.stateCount' <<< "$segment_json")"
      expected_replay_count="$(jq -r '.replayCount' <<< "$segment_json")"
      expected_resume_setup_count="$(jq -r '.resumeSetup.rowCount // 0' <<< "$segment_json")"
      expected_plan_sha256="$(shasum -a 256 Scripts/s10-4-segment-plan.json | awk '{print toupper($1)}')"
      expected_evidence_kernel_sha256="$(jq -r '.evidenceKernelSHA256' Scripts/s10-4-segment-plan.json)"
      expected_selector_sha256="$(shasum -a 256 Scripts/ci-selection.json | awk '{print toupper($1)}')"
      expected_shard_contract_sha256="$(shasum -a 256 Scripts/s10-4-shards.json | awk '{print toupper($1)}')"
      expected_inventory_sha256="$(shasum -a 256 docs/design/s10/s10-screen-state-inventory.json | awk '{print toupper($1)}')"
      expected_common_task_schema_sha256="$(shasum -a 256 docs/design/s10/s10-accessibility-common-tasks.json | awk '{print toupper($1)}')"
      expected_unit_executed_test_selectors="$(jq -c '
        [.. | objects
          | select(.nodeType? == "Test Case" and .result? == "Passed")
          | .nodeIdentifier]
        | unique | sort
      ' "$CI_ARTIFACT_DIR/unit-test-results.json")"
      expected_ui_executed_test_selectors="$(jq -c '
        [.. | objects
          | select(.nodeType? == "Test Case" and .result? == "Passed")
          | .nodeIdentifier]
        | unique | sort
      ' "$CI_ARTIFACT_DIR/ui-test-results.json")"
      expected_attachment_count="$(jq '[.[]?.attachments[]?] | length' \
        "$shard_evidence_path/xcresult-attachment-manifest.json")"
      test "$expected_attachment_count" -eq "$((expected_state_count + 1))"
      require_nonempty_directory "$shard_evidence_path/candidates"
      test "$(find "$shard_evidence_path/candidates" -type f -name 'state.*.png' \
        | wc -l | tr -d ' ')" -eq "$expected_state_count"
      test -s "$shard_evidence_path/xcresult-attachment-manifest.json"
      test -s "$shard_evidence_path/candidate-exports.json"
      test -s "$shard_evidence_path/candidate-files.json"
      test -s "$shard_evidence_path/state-ax.ndjson"
      test -s "$shard_evidence_path/state-ax.json"
      test -s "$shard_evidence_path/contrast.ndjson"
      test -s "$shard_evidence_path/contrast.json"
      test -s "$shard_evidence_path/replay-rows.json"
      test -s "$shard_evidence_path/resume-setup-rows.json"
      test -s "$shard_evidence_path/segment-receipt.pending.json"
      test ! -e "$shard_evidence_path/segment-receipt.json"
      test ! -e "$shard_evidence_path/shard-receipt.json"
      test "$(jq 'length' "$shard_evidence_path/candidate-files.json")" \
        -eq "$expected_state_count"
      test "$(jq 'length' "$shard_evidence_path/state-ax.json")" \
        -eq "$expected_state_count"
      test "$(jq 'length' "$shard_evidence_path/contrast.json")" \
        -eq "$expected_state_count"
      test "$(jq 'length' "$shard_evidence_path/replay-rows.json")" \
        -eq "$expected_replay_count"
      test "$(jq 'length' "$shard_evidence_path/resume-setup-rows.json")" \
        -eq "$expected_resume_setup_count"
      state_ax_path="$CI_ARTIFACT_DIR/ax/$CI_S10_4_SHARD_ID"
      state_contrast_path="$CI_ARTIFACT_DIR/contrast/$CI_S10_4_SHARD_ID"
      require_nonempty_directory "$state_ax_path"
      require_nonempty_directory "$state_contrast_path"
      test "$(find "$state_ax_path" -type f -name 'state.*.json' | wc -l | tr -d ' ')" \
        -eq "$expected_state_count"
      test "$(find "$state_contrast_path" -type f -name 'state.*.json' | wc -l | tr -d ' ')" \
        -eq "$expected_state_count"
      test ! -e "$CI_ARTIFACT_DIR/accessibility/$CI_S10_4_SHARD_ID"
      jq -e --arg segment "$CI_S10_4_SEGMENT_ID" \
        --arg head "$GITHUB_SHA" \
        --arg ref "$GITHUB_REF" \
        --arg run "$GITHUB_RUN_ID" \
        --arg job "$GITHUB_JOB" \
        --arg artifactName "ios-ci-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT-$CI_S10_4_SHARD_ID-$CI_S10_4_SEGMENT_ID" \
        --arg planSHA256 "$expected_plan_sha256" \
        --arg evidenceKernelSHA256 "$expected_evidence_kernel_sha256" \
        --arg selectorSHA256 "$expected_selector_sha256" \
        --arg shardContractSHA256 "$expected_shard_contract_sha256" \
        --arg inventorySHA256 "$expected_inventory_sha256" \
        --arg commonTaskSchemaSHA256 "$expected_common_task_schema_sha256" \
        --argjson unitTestSelectors "$expected_unit_executed_test_selectors" \
        --argjson uiTestSelectors "$expected_ui_executed_test_selectors" \
        --argjson attachmentCount "$expected_attachment_count" \
        --argjson segmentPlan "$segment_json" \
        --argjson stateCount "$expected_state_count" \
        --argjson replayCount "$expected_replay_count" \
        --argjson resumeSetupRowCount "$expected_resume_setup_count" '
          .schemaVersion == 1
          and .receiptKind == "s10.4-segment-pending"
          and .complete == false
          and .finalAcceptanceEligible == false
          and .segmentID == $segment
          and .productHead == $head
          and .ref == $ref
          and .runID == $run
          and .jobID == $job
          and .artifactName == $artifactName
          and .segmentPlanSHA256 == $planSHA256
          and .evidenceKernelSHA256 == $evidenceKernelSHA256
          and .selectorSHA256 == $selectorSHA256
          and .shardContractSHA256 == $shardContractSHA256
          and .inventorySHA256 == $inventorySHA256
          and .commonTaskSchemaSHA256 == $commonTaskSchemaSHA256
          and .sdkName == "iphonesimulator26.5"
          and .sdkBuild == "23F81a"
          and .xcodeVersion == "Xcode 26.6"
          and .xcodeBuild == "17F113"
          and .runnerProvider == "github"
          and .runnerLabel == "macos-26"
          and .simulatorRuntime == "iOS 26.2"
          and .simulatorRuntimeBuild == "23C54"
          and .simulatorName == "iPhone 17"
          and .buildMode == "independent-build-for-testing"
          and .crossSessionBuildReuse == false
          and .crossSessionTestWithoutBuilding == false
          and .unitExecutedTestCount == 5
          and .uiExecutedTestCount == 1
          and .unitTestSelectors == $unitTestSelectors
          and (.unitTestSelectors | length) == 5
          and .uiTestSelectors == $uiTestSelectors
          and (.uiTestSelectors | length) == 1
          and .attachmentCount == $attachmentCount
          and .segmentTerminalAttachmentCount == 1
          and .ordinal == $segmentPlan.ordinal
          and .startOrdinal == $segmentPlan.startOrdinal
          and .endOrdinal == $segmentPlan.endOrdinal
          and .resumeMode == $segmentPlan.resumeMode
          and .dependencySegmentIDs == $segmentPlan.dependencySegmentIDs
          and .dependencyOwnedStateCount == $segmentPlan.dependencyOwnedStateCount
          and .dependencyOwnedStateIDs == $segmentPlan.dependencyOwnedStateIDs
          and .dependencyOwnedStateSHA256 == $segmentPlan.dependencyOwnedStateSHA256
          and .resumeSetup == $segmentPlan.resumeSetup
          and .ownedStateIDs == $segmentPlan.ownedStateIDs
          and .replayStateIDs == $segmentPlan.replayStateIDs
          and .ownedStateSHA256 == $segmentPlan.ownedStateSHA256
          and .replayStateSHA256 == $segmentPlan.replayStateSHA256
          and .stateCount == $stateCount
          and .replayCount == $replayCount
          and .markerCount == $stateCount
          and .replayRowCount == $replayCount
          and .resumeSetupRowCount == $resumeSetupRowCount
          and .diagnosticCount == 0
          and .candidateCount == $stateCount
          and .stateAXRowCount == $stateCount
          and .contrastRowCount == $stateCount
          and .accessibilityRowCount == 0
          and (.buildIdentitySHA256 | test("^[0-9A-F]{64}$"))
          and (.unitIdentitySHA256 | test("^[0-9A-F]{64}$"))
          and (.uiIdentitySHA256 | test("^[0-9A-F]{64}$"))
          and (.sessionIdentitySHA256 | test("^[0-9A-F]{64}$"))
        ' "$shard_evidence_path/segment-receipt.pending.json" > /dev/null
      for evidence_file in "$state_ax_path"/*.json; do
        jq -e --arg shard "$CI_S10_4_SHARD_ID" --arg productHead "$GITHUB_SHA" '
          .shardID == $shard
          and .sourceProductHead == $productHead
          and (.evidenceID == ("s10.4-ax-" + $shard + "-" + .stateID))
          and (.axTreeSHA256 | test("^[0-9A-F]{64}$"))
        ' "$evidence_file" > /dev/null
      done
      for evidence_file in "$state_contrast_path"/*.json; do
        jq -e --arg shard "$CI_S10_4_SHARD_ID" --arg productHead "$GITHUB_SHA" '
          .shardID == $shard
          and .sourceProductHead == $productHead
          and (.evidenceID == ("s10.4-contrast-" + $shard + "-" + .stateID))
          and (.axTreeSHA256 | test("^[0-9A-F]{64}$"))
        ' "$evidence_file" > /dev/null
      done
    else
    require_nonempty_directory "$shard_evidence_path/candidates"
    test "$(find "$shard_evidence_path/candidates" -type f -name 'state.*.png' \
      | wc -l | tr -d ' ')" -eq 67
    test -s "$shard_evidence_path/xcresult-attachment-manifest.json"
    test -s "$shard_evidence_path/candidate-exports.json"
    test -s "$shard_evidence_path/candidate-files.json"
    test -s "$shard_evidence_path/accessibility.ndjson"
    test -s "$shard_evidence_path/accessibility.json"
    test -s "$shard_evidence_path/contrast.ndjson"
    test -s "$shard_evidence_path/contrast.json"
    test -s "$shard_evidence_path/shard-receipt.json"
    test "$(jq 'length' "$shard_evidence_path/candidate-files.json")" -eq 67
    test "$(jq 'length' "$shard_evidence_path/accessibility.json")" -eq 6
    test "$(jq 'length' "$shard_evidence_path/contrast.json")" -eq 67
    state_ax_path="$CI_ARTIFACT_DIR/ax/$CI_S10_4_SHARD_ID"
    state_contrast_path="$CI_ARTIFACT_DIR/contrast/$CI_S10_4_SHARD_ID"
    task_accessibility_path="$CI_ARTIFACT_DIR/accessibility/$CI_S10_4_SHARD_ID"
    require_nonempty_directory "$state_ax_path"
    require_nonempty_directory "$state_contrast_path"
    require_nonempty_directory "$task_accessibility_path"
    test "$(find "$state_ax_path" -type f -name 'state.*.json' | wc -l | tr -d ' ')" -eq 67
    test "$(find "$state_contrast_path" -type f -name 'state.*.json' | wc -l | tr -d ' ')" -eq 67
    test "$(find "$task_accessibility_path" -type f -name '*.json' | wc -l | tr -d ' ')" -eq 6

    jq -r '.routes[].states[].state_id + ".json"' \
      docs/design/s10/s10-screen-state-inventory.json \
      | LC_ALL=C sort > "$RUNNER_TEMP/s10-4-expected-state-evidence-files.txt"
    find "$state_ax_path" -type f -name 'state.*.json' -exec basename {} \; \
      | LC_ALL=C sort > "$RUNNER_TEMP/s10-4-observed-ax-files.txt"
    find "$state_contrast_path" -type f -name 'state.*.json' -exec basename {} \; \
      | LC_ALL=C sort > "$RUNNER_TEMP/s10-4-observed-contrast-files.txt"
    cmp -s "$RUNNER_TEMP/s10-4-expected-state-evidence-files.txt" \
      "$RUNNER_TEMP/s10-4-observed-ax-files.txt"
    cmp -s "$RUNNER_TEMP/s10-4-expected-state-evidence-files.txt" \
      "$RUNNER_TEMP/s10-4-observed-contrast-files.txt"

    jq -r '.tasks[].task_id + ".json"' \
      docs/design/s10/s10-accessibility-common-tasks.json \
      | LC_ALL=C sort > "$RUNNER_TEMP/s10-4-expected-task-evidence-files.txt"
    find "$task_accessibility_path" -type f -name '*.json' -exec basename {} \; \
      | LC_ALL=C sort > "$RUNNER_TEMP/s10-4-observed-task-evidence-files.txt"
    cmp -s "$RUNNER_TEMP/s10-4-expected-task-evidence-files.txt" \
      "$RUNNER_TEMP/s10-4-observed-task-evidence-files.txt"

    for evidence_file in "$state_ax_path"/*.json; do
      jq -e \
        --arg shard "$CI_S10_4_SHARD_ID" \
        --arg productHead "$GITHUB_SHA" '
          .shardID == $shard
          and .sourceProductHead == $productHead
          and (.evidenceID == ("s10.4-ax-" + $shard + "-" + .stateID))
          and (.axTreeSHA256 | test("^[0-9A-F]{64}$"))
        ' "$evidence_file" > /dev/null
    done
    for evidence_file in "$state_contrast_path"/*.json; do
      jq -e \
        --arg shard "$CI_S10_4_SHARD_ID" \
        --arg productHead "$GITHUB_SHA" '
          .shardID == $shard
          and .sourceProductHead == $productHead
          and (.evidenceID == ("s10.4-contrast-" + $shard + "-" + .stateID))
          and (.axTreeSHA256 | test("^[0-9A-F]{64}$"))
        ' "$evidence_file" > /dev/null
    done
    for evidence_file in "$task_accessibility_path"/*.json; do
      jq -e \
        --arg shard "$CI_S10_4_SHARD_ID" \
        --arg productHead "$GITHUB_SHA" '
          .shardID == $shard
          and .sourceProductHead == $productHead
          and (.evidenceID == ("s10.4-ax-" + $shard + "-" + .taskID))
          and (.focusOrderEvidenceID == ("s10.4-focus-order-" + $shard + "-" + .taskID))
          and (.targetSizeEvidenceID == ("s10.4-target-size-" + $shard + "-" + .taskID))
          and (.contrastEvidenceID == ("s10.4-contrast-" + $shard + "-" + .taskID))
        ' "$evidence_file" > /dev/null
    done
    fi
  fi
else
  test "${CI_RUN_UI_SMOKE:-}" = "false"
  test ! -e "$CI_ARTIFACT_DIR/ui-smoke.log"
  test ! -e "$CI_ARTIFACT_DIR/UISmoke.xcresult"
  test ! -e "$CI_ARTIFACT_DIR/ui-final.png"
fi
