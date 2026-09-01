#!/bin/bash

set -euo pipefail

mode="${1:---unsigned}"
expected_main_sha="${2:-}"

case "$mode" in
  --unsigned) ;;
  --release-ready)
    [[ "$expected_main_sha" =~ ^[0-9a-f]{40}$ ]]
    ;;
  *)
    printf 'usage: %s [--unsigned | --release-ready <expected-main-sha>]\n' "$0" >&2
    exit 64
    ;;
esac

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repository_root"

manifest="Release/ReleaseInputManifestV1.json"
values="Release/ProvidedReleaseValuesV1.json"
metadata="Release/UnsignedRCMetadataV1.json"
privacy="FieldEvidenceApp/PrivacyInfo.xcprivacy"
smokes="Release/LaunchSmokeEvidenceIndexV1.json"
discovery_truth="FieldEvidenceAppTests/Fixtures/V21/DiscoveryTruth/V23P04C15DiscoveryTruthCorpusV1.json"
export_options="Release/TestFlightExportOptions.plist"
workflow=".github/workflows/testflight.yml"
project="FieldEvidenceApp.xcodeproj/project.pbxproj"

for path in \
  "$manifest" \
  "$values" \
  "$metadata" \
  "$privacy" \
  "$smokes" \
  "$discovery_truth" \
  "$export_options" \
  "$workflow" \
  "$project"
do
  test -f "$path"
  test ! -L "$path"
  test -s "$path"
done

source_contract_result="$(python3 -B Scripts/v23/verify_p04_c15_contracts.py --source-contracts --json)"
jq -e '
  .cardID == "V23-P04-C15"
  and .mode == "source-contracts"
  and .result == "PASS_STATIC_PROVISIONAL"
  and .sourceReady == true
  and .sourceContracts.sourceReady == true
  and .sourceContracts.sourceCount == 7
  and .sourceContracts.proofCount == 6
  and (.failures | length) == 0
  and .flagsAllFalse == true
' <<<"$source_contract_result" >/dev/null

source_contract_self_test_result="$(python3 -B Scripts/v23/verify_p04_c15_contracts.py --source-contracts-self-test --json)"
jq -e '
  .cardID == "V23-P04-C15"
  and .mode == "source-contracts-self-test"
  and .result == "PASS_STATIC_PROVISIONAL"
  and .sourceReady == true
  and .sourceContracts.sourceCount == 7
  and .sourceContracts.proofCount == 6
  and .sourceContractsSelfTest.sourceContractsSelfTest == "PASS"
  and .sourceContractsSelfTest.count == 8
  and .sourceContractsSelfTest.rejected == [
    "brand-root-opaque",
    "synthetic-sample-opaque",
    "aggregate-evidence-opaque",
    "accessibility-root-opaque",
    "privacy-artifact-opaque",
    "catalog-ref-opaque",
    "candidate-digest-wrong",
    "approval-extra-key"
  ]
  and (.failures | length) == 0
  and .flagsAllFalse == true
' <<<"$source_contract_self_test_result" >/dev/null

generator_interrupt_result="$(python3 -B Scripts/v23/generate_p04_c15_contracts.py --self-test)"
case "$generator_interrupt_result" in
  "C15 interruption self-test PASS "*) ;;
  *) exit 65 ;;
esac

jq -e '
  keys == [
    "acquisition",
    "artifacts",
    "authority",
    "cardID",
    "catalog",
    "containsCustomerData",
    "containsSecrets",
    "expectedDispositions",
    "hostileCases",
    "immutable",
    "journalFaultBoundaries",
    "lifecycleCoverage",
    "ordinal",
    "productState",
    "publicState",
    "publication",
    "recovery",
    "requirements",
    "schema",
    "schemaVersion",
    "selectors",
    "semantics",
    "statusFlags",
    "synthetic",
    "testOnly",
    "uiAdoptionSkipped"
  ]
  and .schema == "V23P04C15DiscoveryTruthCorpusV1"
  and .schemaVersion == 1
  and .cardID == "V23-P04-C15"
  and .ordinal == 103
  and .testOnly == true
  and .synthetic == true
  and .immutable == true
  and .containsCustomerData == false
  and .containsSecrets == false
  and .uiAdoptionSkipped == true
  and (.authority | keys) == ["contextDigest", "finalHashesSealed", "pathFenceDigest", "sequence"]
  and (.authority.contextDigest | test("^[0-9a-f]{64}$"))
  and (.authority.pathFenceDigest | test("^[0-9a-f]{64}$"))
  and .authority.sequence == 448
  and .authority.finalHashesSealed == false
  and (.semantics | keys) == [
    "aggregateNoJoinKey",
    "aggregateNoRealData",
    "persistentContractMode",
    "persistentContractSchema",
    "publicationEligible",
    "sixProofKinds",
    "uiAdoption"
  ]
  and .semantics.persistentContractMode == "DECLARATION_ONLY"
  and .semantics.persistentContractSchema == "DISCOVERY_TRUTH_CATALOG_V1"
  and .semantics.publicationEligible == false
  and .semantics.sixProofKinds == [
    "CAPABILITY",
    "EVIDENCE",
    "BRAND",
    "CANDIDATE",
    "APPROVAL",
    "EXPIRY_SUPERSESSION"
  ]
  and .semantics.aggregateNoJoinKey == true
  and .semantics.aggregateNoRealData == true
  and .semantics.uiAdoption == "POST_S10_6_SKIP_NO_CREDIT"
  and (.selectors | map(.id)) == ["G01", "A01", "H01", "I01", "R01"]
  and (.selectors | map(.tier)) == ["GOLDEN", "ALTERNATE", "HOSTILE", "INTERRUPTION", "RECOVERY"]
  and (.selectors | map(.selector)) == [
    "testV23P04C15G01DiscoveryTruthCatalogValidatesLocalizedLimitsAndClosedArtifactSet",
    "testV23P04C15A01CategoriesAndAppTagsRemainSeparateTypedSets",
    "testV23P04C15H01HostileOpaqueStaleRealDataAndDraftPublishedInputsFailClosed",
    "testV23P04C15I01InterruptedDeclarationGenerationLeavesZeroPartialOrCompleteArtifactSet",
    "testV23P04C15R01DeletingAndRebuildingDeclarationArtifactsLeavesProductAndPublicStateUnchanged"
  ]
  and (.requirements | keys) == [
    "aggregateEvidenceHasNoStableJoinKeys",
    "candidateAndBrandRevisionBindExactly",
    "categoriesAndAppTagsAreSeparate",
    "closedLocalizedPlatformLimits",
    "declarationDeletionPreservesProductAndPublicState",
    "interruptionIsZeroPartialOrComplete",
    "publicationProviderAndNetworkDisabled",
    "staticProofKindsAreClosed",
    "syntheticSamplesOnly",
    "unapprovedClaimsDisabledOrDeferred"
  ]
  and all(.requirements[]; . == true)
  and (.catalog | keys) == ["appTags", "candidate", "categories", "claims", "locales", "screenshots"]
  and (.catalog.candidate | keys) == [
    "brandBaselineID",
    "brandRevision",
    "brandRevisionSHA256",
    "candidateID",
    "status"
  ]
  and .catalog.candidate.candidateID == "c15-candidate-synthetic-v1"
  and .catalog.candidate.status == "DRAFT_ONLY"
  and .catalog.candidate.brandBaselineID == "c15-brand-baseline-synthetic-v1"
  and .catalog.candidate.brandRevision == "c15-brand-revision-v1"
  and (.catalog.candidate.brandRevisionSHA256 | test("^[0-9a-f]{64}$"))
  and (.catalog.locales | map(.locale)) == ["en-US", "fr-FR"]
  and all(.catalog.locales[];
    (. | keys) == ["description", "keywords", "locale", "name", "promotionalText", "subtitle"]
    and (.locale == "en-US" or .locale == "fr-FR")
    and (.name | type) == "string"
    and (.name | length) > 0
    and (.name | length) <= 30
    and (.subtitle | type) == "string"
    and (.subtitle | length) > 0
    and (.subtitle | length) <= 30
    and (.keywords | type) == "string"
    and (.keywords | utf8bytelength) <= 100
    and (.promotionalText | type) == "string"
    and (.promotionalText | length) <= 170
    and (.description | type) == "string"
    and (.description | length) <= 4000
  )
  and .catalog.categories == ["BUSINESS", "PRODUCTIVITY"]
  and .catalog.appTags == ["EVIDENCE", "FIELD_WORK"]
  and ((.catalog.categories | unique) - .catalog.appTags | length) == 2
  and ((.catalog.appTags | unique) - .catalog.categories | length) == 2
  and (.catalog.screenshots | map(.id)) == ["c15-shot-home-v1", "c15-shot-report-v1"]
  and (.catalog.screenshots | map(.surface)) == ["HOME", "SAMPLE_REPORT"]
  and all(.catalog.screenshots[];
    (. | keys) == ["artifactID", "id", "publishable", "status", "surface"]
    and .status == "DRAFT_ONLY"
    and .publishable == false
  )
  and (.catalog.claims | map(.id)) == ["verified-outcomes", "ratings", "privacy-certification"]
  and all(.catalog.claims[];
    (. | keys) == ["enabled", "evidenceID", "id", "status"]
    and .enabled == false
    and .status == "DISABLED_OR_DEFERRED"
    and .evidenceID == null
  )
  and (.artifacts | map(.kind)) == ["HOME", "USE_CASE", "PRIVACY", "ACCESSIBILITY", "SUPPORT", "SAMPLE_REPORT"]
  and (.artifacts | map(.id)) == [
    "c15-home-proof-v1",
    "c15-use-case-proof-v1",
    "c15-privacy-proof-v1",
    "c15-accessibility-proof-v1",
    "c15-support-proof-v1",
    "c15-sample-report-proof-v1"
  ]
  and all(.artifacts[];
    (. | keys) == [
      "containsCustomerData",
      "contentSHA256",
      "id",
      "kind",
      "practiceWorkspace",
      "publishable",
      "status",
      "watermarks"
    ]
    and (.id | test("^(c15-[a-z-]+-v1)$"))
    and (.id | test("customer|person|device|workspace|entity|production|real"; "i") | not)
    and .status == "DRAFT_ONLY"
    and .publishable == false
    and .containsCustomerData == false
    and (.contentSHA256 | test("^[0-9a-f]{64}$"))
    and (.watermarks | type) == "array"
    and (.watermarks | index("SYNTHETIC EXAMPLE — NO CUSTOMER DATA")) != null
    and (if .practiceWorkspace then (.watermarks | index("PRACTICE — NOT FOR FIELD USE")) != null else true end)
  )
  and (.acquisition | keys) == [
    "claimStatus",
    "containsRealData",
    "deviceIdentifiers",
    "enabled",
    "entityIdentifiers",
    "networkAccess",
    "personIdentifiers",
    "provider",
    "source",
    "stableJoinKeys",
    "watermark",
    "workspaceIdentifiers"
  ]
  and .acquisition.enabled == false
  and .acquisition.claimStatus == "DISABLED_OR_DEFERRED"
  and .acquisition.source == "AGGREGATE_SYNTHETIC_FIXTURE"
  and .acquisition.provider == "NONE"
  and .acquisition.networkAccess == false
  and .acquisition.containsRealData == false
  and .acquisition.stableJoinKeys == []
  and .acquisition.personIdentifiers == []
  and .acquisition.deviceIdentifiers == []
  and .acquisition.workspaceIdentifiers == []
  and .acquisition.entityIdentifiers == []
  and .acquisition.watermark == "SYNTHETIC EXAMPLE — NO CUSTOMER DATA"
  and (.publication | keys) == ["deployment", "networkAccess", "provider", "publishable", "signing", "status", "upload"]
  and .publication.status == "DRAFT_ONLY"
  and .publication.publishable == false
  and .publication.upload == false
  and .publication.signing == false
  and .publication.deployment == false
  and .publication.networkAccess == false
  and .publication.provider == "NONE"
  and all(.expectedDispositions[];
    (. | keys) == ["acceptedArtifactCount", "case", "disposition", "productWrites", "publicWrites"]
    and (.acceptedArtifactCount | type) == "number"
    and .acceptedArtifactCount >= 0
    and .productWrites == 0
    and .publicWrites == 0
  )
  and .hostileCases == [
    "ARBITRARY_NONEMPTY_METADATA",
    "PLATFORM_LIMIT_OVERFLOW",
    "UNSUPPORTED_LOCALE",
    "CATEGORY_AS_APP_TAG",
    "STALE_BRAND_REVISION",
    "UNIMPLEMENTED_ENABLED_CLAIM",
    "REAL_DATA_IDENTIFIER",
    "MISSING_SYNTHETIC_WATERMARK",
    "MISSING_PRACTICE_WATERMARK",
    "STABLE_JOIN_KEY",
    "DRAFT_LABELED_PUBLISHED",
    "PUBLICATION_PROVIDER_PATH",
    "NETWORK_ACCESS_PATH"
  ]
  and .journalFaultBoundaries == [
    "BEFORE_ACCEPTED_ARTIFACT_WRITE",
    "AFTER_ARTIFACT_WRITE_BEFORE_RECEIPT",
    "AFTER_RECEIPT_BEFORE_RETURN"
  ]
  and .lifecycleCoverage == [
    "DELETE_DECLARATION_DRAFTS",
    "REBUILD_DECLARATION_DRAFTS",
    "EXPORT_DECLARATION_REPORT",
    "SEARCH_DECLARATION_FIXTURES",
    "REPLAY_DECLARATION_RECEIPT"
  ]
  and (.recovery | keys) == [
    "backupRestore",
    "delete",
    "noProviderConnection",
    "noUpload",
    "preservesProductState",
    "preservesPublicState",
    "rebuild",
    "replay"
  ]
  and .recovery.backupRestore == "NOT_APPLICABLE_DECLARATION_ONLY"
  and .recovery.delete == "DECLARATION_ONLY_ARTIFACTS"
  and .recovery.rebuild == "EXACT_CATALOG_AND_ARTIFACT_SET"
  and .recovery.replay == "ZERO_PARTIAL_OR_ONE_COMPLETE_RECEIPT"
  and .recovery.preservesProductState == true
  and .recovery.preservesPublicState == true
  and .recovery.noProviderConnection == true
  and .recovery.noUpload == true
  and (.productState | keys) == ["canonicalWrites", "mutationReceipts", "publishedRecords", "workspaceRecords"]
  and all(.productState[]; . == 0)
  and (.publicState | keys) == ["networkRequests", "providerConnections", "publishedArtifacts", "uploads"]
  and all(.publicState[]; . == 0)
  and (.statusFlags | keys) == [
    "acceptance",
    "activation",
    "adoption",
    "hosted",
    "hostedAcceptance",
    "native",
    "nativeAcceptance",
    "phase10PollingDuringParallelExecution",
    "physicalEvidence",
    "publish",
    "release",
    "uiAcceptanceCredit"
  ]
  and all(.statusFlags[]; . == false)
' "$discovery_truth" >/dev/null

expected_input_keys="$(
  printf '%s\n' \
    age_rating_answers \
    app_bundle_id \
    app_privacy_answers \
    app_review_information \
    app_store_connect_api_issuer_id \
    app_store_connect_api_key_id \
    app_store_connect_api_private_key \
    app_store_metadata \
    app_store_record \
    app_store_title_clearance \
    apple_account_access \
    apple_developer_program_membership \
    apple_developer_team_id \
    banking_configuration \
    distribution_certificate_p12 \
    distribution_certificate_password \
    export_compliance_answers \
    github_environment_configuration \
    live_billing_grace_period \
    live_family_sharing_setting \
    live_introductory_offer \
    live_subscription_group \
    live_subscription_price \
    live_subscription_product_configuration \
    live_subscription_storefronts \
    monthly_product_id \
    named_sandbox_tester \
    owner_domain \
    paid_apps_agreement \
    physical_iphone_access \
    privacy_policy_url \
    release_build_number \
    release_marketing_version \
    six_of_ten_commitment_evidence \
    small_business_program_status \
    support_email \
    support_url \
    tax_configuration \
    terms_of_use_url \
    ui_test_bundle_id \
    unit_test_bundle_id
)"
actual_input_keys="$(jq -er '.inputs[].key' "$manifest" | tr -d '\r' | LC_ALL=C sort)"
test "$actual_input_keys" = "$expected_input_keys"

jq -e '
  keys == ["inputs", "releaseReady", "schemaVersion"]
  and .schemaVersion == 1
  and (.releaseReady | type) == "boolean"
  and (.inputs | type) == "array"
  and (.inputs | length) == 41
  and (.inputs | map(.key)) == (.inputs | map(.key) | sort)
  and (.inputs | map(.key) | unique | length) == 41
  and all(
    .inputs[];
    keys == [
      "environmentKey",
      "key",
      "requiredFor",
      "secret",
      "source",
      "status",
      "valueKey"
    ]
    and (.key | test("^[a-z0-9_]+$"))
    and (.requiredFor == "S9.1" or .requiredFor == "S9.2" or .requiredFor == "S9.3")
    and (.secret | type) == "boolean"
    and (
      .source == "repository"
      or .source == "owner"
      or .source == "app_store_connect"
      or .source == "github_environment"
    )
    and (.status == "provided" or .status == "pending")
    and (
      if .secret
      then .valueKey == null
        and (.environmentKey | type) == "string"
        and (.environmentKey | test("^[A-Z0-9_]+$"))
      else .environmentKey == null
        and (.valueKey | type) == "string"
        and (.valueKey | test("^[A-Za-z][A-Za-z0-9]+$"))
      end
    )
  )
  and (.releaseReady == (all(.inputs[]; .status == "provided")))
' "$manifest" >/dev/null

jq -e '
  keys == ["schemaVersion", "values"]
  and .schemaVersion == 1
  and (.values | type) == "object"
  and all(.values[]; . != null)
' "$values" >/dev/null

expected_value_keys="$(
  jq -r '
    .inputs[]
    | select(.status == "provided" and .secret == false)
    | .valueKey
  ' "$manifest" | tr -d '\r' | LC_ALL=C sort
)"
actual_value_keys="$(jq -r '.values | keys[]' "$values" | tr -d '\r' | LC_ALL=C sort)"
test "$actual_value_keys" = "$expected_value_keys"

jq -e \
  --slurpfile provided "$values" '
    all(
      .inputs[];
      if .status == "pending" and .secret == false
      then (.valueKey as $key | ($provided[0].values | has($key) | not))
      else true
      end
    )
  ' "$manifest" >/dev/null

jq -e '
  .values.appBundleID == "com.palatis3.fieldrecord"
  and .values.unitTestBundleID == "com.palatis3.fieldrecord.tests"
  and .values.uiTestBundleID == "com.palatis3.fieldrecord.uitests"
  and .values.monthlyProductID == "com.palatis3.fieldrecord.sub.solo.monthly.v1"
' "$values" >/dev/null

jq -e \
  --slurpfile manifest "$manifest" '
  keys == [
    "app",
    "commerce",
    "nonClaims",
    "phaseBaseSHA",
    "privacy",
    "releaseReady",
    "schemaVersion",
    "unsigned"
  ]
  and .schemaVersion == 1
  and .unsigned == true
  and .releaseReady == $manifest[0].releaseReady
  and .commerce.localFixtureIsReleaseAuthority == false
  and .privacy.tracking == false
  and .privacy.collectedDataTypesDeclaredByApp == []
  and (
    if .releaseReady
    then .app.candidateTitleClearanceStatus == "cleared"
      and .app.finalReleaseVersionStatus == "provided"
      and .app.finalReleaseBuildStatus == "provided"
      and .commerce.productionConfigurationStatus == "provided"
    else .app.candidateTitleClearanceStatus == "pending"
      and .app.finalAppStoreTitle == null
      and .app.finalReleaseMarketingVersion == null
      and .app.finalReleaseBuildNumber == null
      and .app.finalReleaseVersionStatus == "pending"
      and .app.finalReleaseBuildStatus == "pending"
      and .commerce.productionConfigurationStatus == "pending"
    end
  )
' "$metadata" >/dev/null

if grep -ERq \
  'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|MII[A-Za-z0-9+/]{32}|AKIA[0-9A-Z]{16}' \
  Release
then
  printf 'release files contain credential-shaped bytes\n' >&2
  exit 65
fi

privacy_json="$(plutil -convert json -o - "$privacy")"
jq -e '
  keys == [
    "NSPrivacyAccessedAPITypes",
    "NSPrivacyCollectedDataTypes",
    "NSPrivacyTracking",
    "NSPrivacyTrackingDomains"
  ]
  and .NSPrivacyTracking == false
  and .NSPrivacyTrackingDomains == []
  and .NSPrivacyCollectedDataTypes == []
  and (
    .NSPrivacyAccessedAPITypes
    | map({key: .NSPrivacyAccessedAPIType, value: .NSPrivacyAccessedAPITypeReasons})
    | from_entries
  ) == {
    "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
    "NSPrivacyAccessedAPICategoryFileTimestamp": ["3B52.1", "C617.1"],
    "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]
  }
' <<<"$privacy_json" >/dev/null

jq -e '
  keys == ["finalRCSmoke", "phaseBaseSHA", "schemaVersion", "smokes"]
  and .schemaVersion == 1
  and .finalRCSmoke.selector == "FieldEvidenceAppUITests/S9_1FinalRCUITests"
  and .finalRCSmoke.evidenceStatus == "pending_current_s9_1_ci"
  and (.smokes | map(.id)) == [1,2,3,4,5,6,7,8,9,10,11,12]
  and (.smokes | map(.key) | unique | length) == 12
  and all(
    .smokes[];
    .automatedStatus == "passed"
    and .ownerVerificationStatus == "pending_s9_2"
    and (.evidence | type) == "array"
    and (.evidence | length) > 0
    and all(
      .evidence[];
      (.card | test("^S[0-8]\\.[0-9]+$"))
      and (.headSHA | test("^[0-9a-f]{40}$"))
      and (.runID | type) == "number"
      and .runID > 0
      and .source == "docs/execution/HANDOFF.md"
    )
  )
' "$smokes" >/dev/null

plutil -lint "$privacy" "$export_options" >/dev/null
test "$(plutil -extract method raw -o - "$export_options")" = "app-store-connect"
test "$(plutil -extract destination raw -o - "$export_options")" = "export"
test "$(plutil -extract signingStyle raw -o - "$export_options")" = "automatic"
test "$(plutil -extract manageAppVersionAndBuildNumber raw -o - "$export_options")" = "false"

grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER = com.palatis3.fieldrecord;' "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER = com.palatis3.fieldrecord.tests;' "$project"
grep -Fq 'PRODUCT_BUNDLE_IDENTIFIER = com.palatis3.fieldrecord.uitests;' "$project"
grep -Fq 'IPHONEOS_DEPLOYMENT_TARGET = 18.0;' "$project"

grep -Fxq '  workflow_dispatch:' "$workflow"
! grep -Eq '^  (push|pull_request|schedule|workflow_run):' "$workflow"
grep -Fq 'cancel-in-progress: false' "$workflow"
grep -Fq 'environment: app-store-connect' "$workflow"
grep -Fq 'test "$GITHUB_REF" = "refs/heads/main"' "$workflow"
grep -Fq 'git ls-remote --exit-code origin refs/heads/main' "$workflow"
grep -Fq 'bash Scripts/release-preflight.sh --release-ready "$REVIEWED_MAIN_SHA"' "$workflow"
test "$(grep -Fxc '            archive' "$workflow")" -eq 1
test "$(grep -Fc '          xcodebuild -exportArchive \' "$workflow")" -eq 1
test "$(grep -Fc '          HOME="$RELEASE_HOME" xcrun altool --upload-app \' "$workflow")" -eq 1
! grep -Eiq 'retry|max-attempts' "$workflow"
test "$(grep -Ec 'uses: actions/[a-z-]+@[0-9a-f]{40}( |$)' "$workflow")" -eq 2
test "$(grep -Ec 'uses: actions/[a-z-]+@' "$workflow")" -eq 2
grep -Fq 'security create-keychain' "$workflow"
grep -Fq 'security delete-keychain' "$workflow"

if [ "$mode" = "--release-ready" ]; then
  jq -e '.releaseReady == true and all(.inputs[]; .status == "provided")' \
    "$manifest" >/dev/null
  jq -e '.releaseReady == true' "$metadata" >/dev/null
  jq -e '
    .values.appleAccountAccessConfirmed == true
    and .values.appleDeveloperProgramActive == true
    and (.values.appleDeveloperTeamID | test("^[A-Z0-9]{10}$"))
    and .values.bankingConfigurationComplete == true
    and .values.githubEnvironmentConfigured == true
    and .values.namedSandboxTesterConfirmed == true
    and .values.paidAppsAgreementActive == true
    and .values.physicalIPhoneAvailable == true
    and .values.sixOfTenCommitmentEvidenceConfirmed == true
    and .values.smallBusinessProgramStatusVerified == true
    and .values.taxConfigurationComplete == true
    and .values.liveBillingGracePeriodDays == 16
    and .values.liveFamilySharingEnabled == false
    and .values.liveIntroductoryOfferDays == 14
    and (.values.liveSubscriptionGroupID | type) == "string"
    and (.values.liveSubscriptionGroupID | length) > 0
    and (.values.liveSubscriptionPriceConfiguration | type) == "object"
    and (.values.liveSubscriptionPriceConfiguration | length) > 0
    and .values.liveSubscriptionProductConfigured == true
    and (.values.liveSubscriptionStorefronts | type) == "array"
    and (.values.liveSubscriptionStorefronts | length) > 0
    and (.values.appStoreRecordID | type) == "string"
    and (.values.appStoreRecordID | length) > 0
    and (.values.appStoreMetadata | type) == "object"
    and (.values.appStoreMetadata | length) > 0
    and (.values.appReviewInformation | type) == "object"
    and (.values.appReviewInformation | length) > 0
    and (.values.appPrivacyAnswers | type) == "object"
    and (.values.appPrivacyAnswers | length) > 0
    and (.values.ageRatingAnswers | type) == "object"
    and (.values.ageRatingAnswers | length) > 0
    and (.values.exportComplianceAnswers | type) == "object"
    and (.values.exportComplianceAnswers | length) > 0
    and (.values.clearedAppStoreTitle | type) == "string"
    and (.values.clearedAppStoreTitle | length) >= 2
    and (.values.clearedAppStoreTitle | length) <= 30
    and (.values.ownerDomain | test("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$"))
    and (.values.supportEmail | test("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$"))
    and (.values.privacyPolicyURL | test("^https://"))
    and (.values.termsOfUseURL | test("^https://"))
    and (.values.supportURL | test("^https://"))
    and (.values.releaseMarketingVersion | test("^[1-9][0-9]*(\\.[0-9]+){1,2}$"))
    and (.values.releaseBuildNumber | test("^[1-9][0-9]*$"))
  ' "$values" >/dev/null
  jq -e \
    --slurpfile provided "$values" '
      .app.finalAppStoreTitle == $provided[0].values.clearedAppStoreTitle
      and .app.finalReleaseMarketingVersion == $provided[0].values.releaseMarketingVersion
      and .app.finalReleaseBuildNumber == $provided[0].values.releaseBuildNumber
    ' "$metadata" >/dev/null
  owner_domain="$(jq -er '.values.ownerDomain' "$values")"
  support_email="$(jq -er '.values.supportEmail' "$values")"
  case "$support_email" in
    *@"$owner_domain"|*@*."$owner_domain") ;;
    *) exit 65 ;;
  esac
  for value_key in privacyPolicyURL termsOfUseURL supportURL; do
    live_url="$(jq -er --arg key "$value_key" '.values[$key]' "$values")"
    case "$live_url" in
      "https://$owner_domain"|"https://$owner_domain/"*|https://*."$owner_domain"|https://*."$owner_domain/"*) ;;
      *) exit 65 ;;
    esac
  done
  test "${GITHUB_REF:-}" = "refs/heads/main"
  test "${GITHUB_SHA:-}" = "$expected_main_sha"
  test "$(git rev-parse HEAD)" = "$expected_main_sha"
  remote_main_sha="$(git ls-remote --exit-code origin refs/heads/main | awk 'NR == 1 { print $1 }')"
  test "$remote_main_sha" = "$expected_main_sha"
fi

pending_count="$(jq '[.inputs[] | select(.status == "pending")] | length' "$manifest")"
printf 'release preflight passed: mode=%s releaseReady=%s pending=%s\n' \
  "$mode" \
  "$(jq -r '.releaseReady' "$manifest")" \
  "$pending_count"
