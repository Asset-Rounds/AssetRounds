#!/bin/bash

set -euo pipefail

derived_data_path="${RUNNER_TEMP:?}/FieldEvidenceDerivedData"
result_bundle_path="${CI_ARTIFACT_DIR:?}/UISmoke.xcresult"
screenshot_path="$CI_ARTIFACT_DIR/ui-final.png"
attachment_export_path="${RUNNER_TEMP:?}/FieldEvidenceUISmokeAttachments"
attachment_manifest_path="$attachment_export_path/manifest.json"
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

xcrun simctl bootstatus "$CI_SIMULATOR_UDID" -b
if xcrun simctl get_app_container "$CI_SIMULATOR_UDID" "$app_bundle_id" app >/dev/null 2>&1; then
  xcrun simctl uninstall "$CI_SIMULATOR_UDID" "$app_bundle_id"
fi

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
