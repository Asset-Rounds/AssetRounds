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
c26_acquisition="docs/product/discovery/V23P04C26AcquisitionContentDraftV1.json"
c26_tags="docs/product/discovery/V23P04C26AppTagDispositionV1.json"
c26_refinement="docs/product/discovery/V23P04C26DiscoveryTruthCatalogRefinementReceiptV1.json"
c26_metadata="docs/product/discovery/V23P04C26MetadataEvidenceReportV1.json"
c26_accessibility="docs/accessibility/V23P04C26SupportContentAccessibilityManifestV1.json"
c26_corpus="FieldEvidenceAppTests/Fixtures/V21/DiscoveryTruth/V23P04C26OrganicFindabilityCorpusV1.json"
c27_inventory="docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json"
c27_corpus="FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C27BrandHIGStateInventoryCorpusV1.json"
c27_contract="docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryContractV1.json"
c27_evidence="docs/design/v23/tooling/V23P04C27BrandHIGStateInventoryEvidenceReceiptV1.json"
c27_impact="docs/design/v23/tooling/V23P04C27BrandImpactManifestV1.json"
c27_tooling_manifest="docs/design/v23/tooling/V23-P04-C27-tooling-manifest.json"
c28_ledger="docs/product/brand/V23P04C28BrandHIGSharedRootCorrectionLedgerV1.json"
c28_corpus="FieldEvidenceAppTests/Fixtures/V21/Brand/V23P04C28BrandHIGSharedRootCorrectionCorpusV1.json"
c28_contract="docs/design/v23/tooling/V23P04C28BrandHIGSharedRootCorrectionContractV1.json"
c28_evidence="docs/design/v23/tooling/V23P04C28BrandHIGSharedRootCorrectionEvidenceReceiptV1.json"
c28_impact="docs/design/v23/tooling/V23P04C28BrandImpactManifestV1.json"
c28_tooling_manifest="docs/design/v23/tooling/V23-P04-C28-tooling-manifest.json"
c28_schema="Scripts/v23/brand-hig-shared-root-correction.schema.json"
c28_contracts_script="Scripts/v23/p04_c28_contracts.py"
c28_generator_script="Scripts/v23/generate_p04_c28_contracts.py"
c28_verifier_script="Scripts/v23/verify_p04_c28_contracts.py"
c28_required_fence_path_count=22
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
  "$c26_acquisition" \
  "$c26_tags" \
  "$c26_refinement" \
  "$c26_metadata" \
  "$c26_accessibility" \
  "$c26_corpus" \
  "$c27_inventory" \
  "$c27_corpus" \
  "$c27_contract" \
  "$c27_evidence" \
  "$c27_impact" \
  "$c27_tooling_manifest" \
  "$c28_ledger" \
  "$c28_corpus" \
  "$c28_contract" \
  "$c28_evidence" \
  "$c28_impact" \
  "$c28_tooling_manifest" \
  "$c28_schema" \
  "$c28_contracts_script" \
  "$c28_generator_script" \
  "$c28_verifier_script" \
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

python3 -B Scripts/v23/generate_p04_c26_contracts.py --check >/dev/null
c26_generator_self_test="$(python3 -B Scripts/v23/generate_p04_c26_contracts.py --self-test --json)"
jq -e '
  .result == "PASS"
  and .protocol == "MANIFEST_LAST_ATOMIC_REPLACE"
  and .rows == [
    {
      "acceptedSetCount": 0,
      "boundary": "BEFORE_ARTIFACTS",
      "manifestLast": true,
      "realWorktreeUnchanged": true,
      "retryAcceptedSetCount": 1,
      "retryDeterministic": true,
      "temporaryRootMayContainIncompleteArtifacts": true
    },
    {
      "acceptedSetCount": 0,
      "boundary": "AFTER_ARTIFACTS_BEFORE_MANIFEST",
      "manifestLast": true,
      "realWorktreeUnchanged": true,
      "retryAcceptedSetCount": 1,
      "retryDeterministic": true,
      "temporaryRootMayContainIncompleteArtifacts": true
    },
    {
      "acceptedSetCount": 1,
      "boundary": "AFTER_MANIFEST",
      "manifestLast": true,
      "realWorktreeUnchanged": true,
      "retryAcceptedSetCount": 1,
      "retryDeterministic": true,
      "temporaryRootMayContainIncompleteArtifacts": false
    }
  ]
  and .deterministicRerun == true
  and .realWorktreeUnchanged == true
  and .temporaryRootIncompleteStatePermitted == true
' <<<"$c26_generator_self_test" >/dev/null
c26_contract_result="$(python3 -B Scripts/v23/verify_p04_c26_contracts.py --complete --json)"
jq -e '
  .cardID == "V23-P04-C26"
  and .result == "PASS_STATIC_PROVISIONAL"
  and .sourceReady == true
  and .finalHashesSealed == false
  and .flagsAllFalse == true
  and .fencePathCount == 16
  and .existingPathCount == 2
  and .newPathCount == 14
  and .counts.changedPathCount == 16
  and .counts.missingPathCount == 0
  and .counts.unownedChangedPathCount == 0
  and .counts.s10ReservationOverlapCount == 0
  and .selectors == [
    "testV23P04C26G01BoundCatalogRefinementAndDisabledPublication",
    "testV23P04C26A01ApprovalAbsenceDefersAllPublication",
    "testV23P04C26H01HostileClaimsBindingsAndMetadataLimitsFailClosed",
    "testV23P04C26I01ExpiryWithdrawalAndInterruptedDraftRecovery",
    "testV23P04C26R01ReleasePreflightAndAccessibilityGateRemainPublicationIneligible"
  ]
  and (.failures | length) == 0
' <<<"$c26_contract_result" >/dev/null

python3 -B - \
  "$c26_acquisition" "$c26_tags" "$c26_refinement" \
  "$c26_metadata" "$c26_accessibility" "$c26_corpus" <<'PY'
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import unicodedata

root = pathlib.Path.cwd()
acquisition, tags, receipt, metadata, accessibility, corpus = (
    json.loads((root / path).read_bytes()) for path in sys.argv[1:]
)
contract = json.loads(
    (root / "docs/design/v23/tooling/V23P04C26OrganicFindabilityContractV1.json").read_bytes()
)
evidence = json.loads(
    (root / "docs/design/v23/tooling/V23P04C26OrganicFindabilityEvidenceReceiptV1.json").read_bytes()
)

def digest(path):
    return hashlib.sha256((root / path).read_bytes()).hexdigest()

def binding_ok(value):
    return (
        set(value) >= {"path", "sha256"}
        and re.fullmatch(r"[0-9a-f]{64}", value["sha256"]) is not None
        and not pathlib.PurePosixPath(value["path"]).is_absolute()
        and ".." not in pathlib.PurePosixPath(value["path"]).parts
        and digest(value["path"]) == value["sha256"]
    )

def evidence_file(relative_path):
    path = pathlib.PurePosixPath(relative_path)
    assert not path.is_absolute() and ".." not in path.parts
    candidates = (
        root / path,
        root.parent / "AssetRounds-v23-coordination" / path,
    )
    matches = [candidate for candidate in candidates if candidate.is_file()]
    assert len(matches) <= 1
    return matches[0] if matches else None

roots = (acquisition, tags, receipt, metadata)
expected_root_keys = (
    {
        "approval", "brandBinding", "cardID", "catalogBinding", "claims", "control",
        "evidenceBindings", "forbiddenCapabilities", "locales", "metadataLimits",
        "ppoHypotheses", "privacyBinding", "publishEligibility", "schema", "schemaVersion",
        "supportPageSpecs", "syntheticAssetBinding",
    },
    {
        "approval", "brandBinding", "cardID", "catalogBinding", "forbiddenCapabilities",
        "locales", "metadataLimits", "observedSuggestions", "privacyBinding",
        "publishEligibility", "schema", "schemaVersion", "syntheticAssetBinding",
    },
    {
        "approval", "artifactBindings", "brandBinding", "cardID", "catalogBinding",
        "catalogRefinement", "forbiddenCapabilities", "locales", "metadataLimits",
        "privacyBinding", "publishEligibility", "schema", "schemaVersion",
        "syntheticAssetBinding",
    },
    {
        "approval", "brandBinding", "cardID", "catalogBinding", "forbiddenCapabilities",
        "limits", "localeMeasurements", "locales", "metadataLimits", "officialSource",
        "privacyBinding", "publishEligibility", "schema", "schemaVersion", "structuredData",
        "syntheticAssetBinding",
    },
)
for value, keys in zip(roots, expected_root_keys):
    assert set(value) == keys

forbidden_capability_keys = {
    "analyticsProvider", "appStoreSubmission", "customerDataUse", "dnsHosting",
    "finalKeywords", "finalScreenshots", "networkAccess", "paidAcquisition",
    "publication", "upload",
}
for value in roots:
    assert value["schemaVersion"] == 1 and value["cardID"] == "V23-P04-C26"
    assert value["publishEligibility"] is False
    assert value["approval"] == {
        "decisionReference": None,
        "sha256": None,
        "status": "DISABLED_OR_DEFERRED",
    }
    assert set(value["forbiddenCapabilities"]) == forbidden_capability_keys
    assert not any(value["forbiddenCapabilities"].values())
    for key in ("catalogBinding", "brandBinding", "privacyBinding", "syntheticAssetBinding"):
        assert binding_ok(value[key])

limits = {
    "nameMinimumCharacters": 2,
    "nameMaximumCharacters": 30,
    "subtitleMaximumCharacters": 30,
    "promotionalTextMaximumCharacters": 170,
    "descriptionMaximumCharacters": 4000,
    "keywordsMaximumCharacters": 100,
    "keywordsMaximumUTF8Bytes": 100,
    "screenshotsMinimumCount": 1,
    "screenshotsMaximumCount": 10,
    "previewsMaximumCount": 3,
    "ppoMaximumTreatments": 3,
}
assert acquisition["metadataLimits"] == limits
assert len(acquisition["ppoHypotheses"]) <= 3
assert acquisition["control"]["hypothesisID"] == "CONTROL"

def tokens(value):
    return set(re.findall(r"[^\W_]+", value.casefold(), flags=re.UNICODE))

for locale in acquisition["locales"]:
    assert limits["nameMinimumCharacters"] <= len(locale["name"]) <= limits["nameMaximumCharacters"]
    assert len(locale["subtitle"]) <= limits["subtitleMaximumCharacters"]
    assert len(locale["promotionalText"]) <= limits["promotionalTextMaximumCharacters"]
    assert len(locale["description"]) <= limits["descriptionMaximumCharacters"]
    assert len(locale["keywords"]) <= limits["keywordsMaximumCharacters"]
    assert len(locale["keywords"].encode("utf-8")) <= limits["keywordsMaximumUTF8Bytes"]
    assert tokens(locale["keywords"]).isdisjoint(tokens(locale["name"] + " " + locale["subtitle"]))
    assert limits["screenshotsMinimumCount"] <= locale["screenshotCount"] <= limits["screenshotsMaximumCount"]
    assert locale["previewCount"] <= limits["previewsMaximumCount"]
    assert locale["finalKeywords"] is False and locale["publishEligibility"] is False

pages = acquisition["supportPageSpecs"]
assert len(pages) == 6
expected_page_tuples = {
    ("ACCESSIBILITY_SUPPORT", "/support/accessibility-and-support", "c26-accessibility-support-v1", "V23-P04-C16"),
    ("DAY_NIGHT_EVIDENCE", "/support/day-night-evidence", "c26-day-night-evidence-v1", "V23-P04-C18"),
    ("LIGHTING_WORKFLOW_LIMITS", "/support/lighting-workflow-limits", "c26-lighting-workflow-limits-v1", "V23-P04-C17"),
    ("OFFLINE_PLAN_REBASE", "/support/offline-plan-rebase", "c26-offline-plan-rebase-v1", "V23-P04-C19"),
    ("QR_BARCODE_ROUNDS", "/support/qr-barcode-rounds", "c26-qr-barcode-rounds-v1", "V23-P04-C21"),
    ("SURVEY_VERSUS_INSPECTION", "/support/survey-versus-inspection", "c26-survey-versus-inspection-v1", "V23-P04-C20"),
}
assert {
    (page["pageID"], page["canonicalURLPath"], page["claimID"], page["acceptedFeatureCardID"])
    for page in pages
} == expected_page_tuples
assert all(
    page["sourceIsSyntheticOnly"] is True
    and page["status"] == "DISABLED_OR_DEFERRED"
    and {"article", "h1"} <= set(page["semanticHTML"])
    and page["structuredDataVisibleFields"] == ["headline", "description", "limitations"]
    and page["limitations"]
    for page in pages
)

def canonical_digest(value):
    data = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
    ).encode("utf-8") + b"\n"
    return hashlib.sha256(data).hexdigest()

def page_tokens(page):
    content = " ".join((page["title"], page["summary"], *page["limitations"]))
    normalized = unicodedata.normalize("NFKC", content).casefold()
    return set(re.findall(r"[^\W_]+", normalized, flags=re.UNICODE))

page_digests = {}
page_token_sets = {page["pageID"]: page_tokens(page) for page in pages}
for page in pages:
    visible = {
        "headline": page["title"],
        "description": page["summary"],
        "limitations": page["limitations"],
    }
    content_digest = canonical_digest(visible)
    assert page["visibleContentSHA256"] == content_digest
    assert page["structuredDataSHA256"] == content_digest
    page_digests[page["pageID"]] = content_digest

for page in pages:
    own_tokens = page_token_sets[page["pageID"]]
    overlaps = []
    for other in pages:
        if other["pageID"] == page["pageID"]:
            continue
        other_tokens = page_token_sets[other["pageID"]]
        union = own_tokens | other_tokens
        overlaps.append((len(own_tokens & other_tokens) * 10000) // len(union))
    assert page["comparedPageContentSHA256s"] == sorted(
        digest for page_id, digest in page_digests.items() if page_id != page["pageID"]
    )
    assert page["maximumPairwiseTokenOverlapBasisPoints"] == max(overlaps)
    assert page["nearDuplicateThresholdBasisPoints"] == 8000
    assert max(overlaps) < page["nearDuplicateThresholdBasisPoints"]
    originality = {
        "pageID": page["pageID"],
        "visibleContentSHA256": page["visibleContentSHA256"],
        "comparedPageContentSHA256s": page["comparedPageContentSHA256s"],
        "maximumPairwiseTokenOverlapBasisPoints": page["maximumPairwiseTokenOverlapBasisPoints"],
        "nearDuplicateThresholdBasisPoints": page["nearDuplicateThresholdBasisPoints"],
    }
    assert page["originalityComparisonSHA256"] == canonical_digest(originality)

claims = acquisition["claims"]
assert {claim["claimID"] for claim in claims} == {page["claimID"] for page in pages}
page_by_claim = {page["claimID"]: page for page in pages}
assert len(page_by_claim) == len(pages) == len(claims)
assert set(evidence) == {
    "authority", "cardID", "claimAuthorityProjection", "contractDigest",
    "generatorInterruptionProtocol", "provisional", "schema", "schemaVersion",
    "sourceProjection", "statusFlags",
}
authority_rows = evidence["claimAuthorityProjection"]
assert len(authority_rows) == 6
authority_by_card = {row["cardID"]: row for row in authority_rows}
assert len(authority_by_card) == 6
authority_keys = {
    "acceptedHead", "acceptedTree", "cardID", "checkpointDigest", "checkpointPath",
    "checkpointSHA256", "compatibilityDisposition", "currentness", "receiptDigest",
    "recoveryProof", "verificationPath", "verificationSHA256", "claimID",
}
verification_schemas = {
    "V23-P04-C16": "ProvisionalP04C16StaticVerificationReceiptV1",
    "V23-P04-C17": "ProvisionalP04C17StaticVerificationReceiptV1",
    "V23-P04-C18": "ProvisionalP04C18StaticVerificationReceiptV1",
    "V23-P04-C19": "ProvisionalVerificationReceiptV1",
    "V23-P04-C20": "ProvisionalVerificationReceiptV1",
    "V23-P04-C21": "ProvisionalVerificationReceiptV1",
}
for claim in claims:
    current = claim["acceptanceBinding"]
    assert claim["status"] == "DISABLED_OR_DEFERRED" and claim["publishEligibility"] is False
    assert re.fullmatch(r"[0-9a-f]{64}", claim["receiptSHA256"])
    assert current["currentness"] == "CHECKPOINTED_CURRENT"
    assert current["compatibilityDisposition"] == "CURRENT_NOT_SUPERSEDED"
    assert current["recoveryProof"] == "MATCHING_PROVISIONAL_VERIFICATION_RECEIPT"
    card_id = claim["acceptedFeatureCard"]
    assert page_by_claim[claim["claimID"]]["acceptedFeatureCardID"] == card_id
    assert current["checkpointPath"] == f"receipts/{card_id}-provisional-checkpoint.json"
    assert current["verificationPath"] == f"receipts/{card_id}-provisional-verification.json"
    authority = authority_by_card[card_id]
    assert set(authority) == authority_keys
    assert authority == {
        "acceptedHead": current["acceptedCandidateHead"],
        "acceptedTree": current["acceptedCandidateTree"],
        "cardID": card_id,
        "claimID": claim["claimID"],
        "checkpointDigest": current["checkpointDigest"],
        "checkpointPath": current["checkpointPath"],
        "checkpointSHA256": current["checkpointSHA256"],
        "compatibilityDisposition": current["compatibilityDisposition"],
        "currentness": current["currentness"],
        "receiptDigest": claim["receiptSHA256"],
        "recoveryProof": current["recoveryProof"],
        "verificationPath": current["verificationPath"],
        "verificationSHA256": current["verificationSHA256"],
    }
    checkpoint_path = evidence_file(current["checkpointPath"])
    verification_path = evidence_file(current["verificationPath"])
    if checkpoint_path is None or verification_path is None:
        # Portable hosted checkouts consume the closed, generated, manifest-bound
        # authority projection. Windows generation resolves and hashes both files.
        assert checkpoint_path is None and verification_path is None
        assert claim["expiry"] is None and claim["supersededByClaimDigest"] is None
        continue
    assert hashlib.sha256(checkpoint_path.read_bytes()).hexdigest() == current["checkpointSHA256"]
    assert hashlib.sha256(verification_path.read_bytes()).hexdigest() == current["verificationSHA256"]
    checkpoint = json.loads(checkpoint_path.read_bytes())
    verification = json.loads(verification_path.read_bytes())
    assert checkpoint["schema"] == "ProvisionalCardCheckpointReceiptV1"
    assert verification["schema"] == verification_schemas[card_id]
    assert checkpoint["cardID"] == verification["cardID"] == card_id
    assert checkpoint["acceptedCandidateHead"] == verification["acceptedCandidateHead"] == current["acceptedCandidateHead"]
    assert checkpoint["acceptedCandidateTree"] == verification["acceptedCandidateTree"] == current["acceptedCandidateTree"]
    assert checkpoint["checkpointDigest"] == current["checkpointDigest"]
    assert checkpoint["verificationReceiptDigest"] == verification["receiptDigest"] == claim["receiptSHA256"]
    assert checkpoint["canonicalState"] == "CHECKPOINTED"
    assert checkpoint["flagsAllFalse"] is True
    if card_id in {"V23-P04-C16", "V23-P04-C17", "V23-P04-C18", "V23-P04-C19"}:
        assert checkpoint["finalHashesSealed"] is True
    else:
        assert "finalHashesSealed" not in checkpoint
    assert verification["finalHashesSealed"] is True and verification["flagsAllFalse"] is True
    assert verification["sourceReady"] is True
    assert verification["releaseReady"] is False
    assert verification["acceptanceEnabled"] is False
    assert verification["adoptionEnabled"] is False
    if card_id in {"V23-P04-C16", "V23-P04-C17", "V23-P04-C18"}:
        assert verification["complete"] is True
        assert verification["completeVerifierResult"] == verification["result"] == "PASS_STATIC_PROVISIONAL"
    elif card_id in {"V23-P04-C19", "V23-P04-C20"}:
        assert verification["verificationStatus"] == "PASS_STATIC_PROVISIONAL"
    else:
        assert verification["toolingVerifierStatus"] == "PASS_STATIC_PROVISIONAL"
    assert subprocess.run(
        ["git", "rev-parse", f"{current['acceptedCandidateHead']}^{{tree}}"],
        cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip() == current["acceptedCandidateTree"]
    assert claim["expiry"] is None and claim["supersededByClaimDigest"] is None
assert {claim["acceptedFeatureCard"] for claim in claims} == set(authority_by_card)

protocol = evidence["generatorInterruptionProtocol"]
assert set(protocol) == {
    "deterministicRerun", "protocol", "realWorktreeUnchanged", "rows",
    "temporaryRootIncompleteStatePermitted",
}
assert protocol["protocol"] == "MANIFEST_LAST_ATOMIC_REPLACE"
assert protocol["deterministicRerun"] is True
assert protocol["realWorktreeUnchanged"] is True
assert protocol["temporaryRootIncompleteStatePermitted"] is True
assert protocol["rows"] == [
    {
        "boundary": "BEFORE_ARTIFACTS", "acceptedSetCount": 0,
        "manifestLast": True, "realWorktreeUnchanged": True,
        "retryAcceptedSetCount": 1, "retryDeterministic": True,
        "temporaryRootMayContainIncompleteArtifacts": True,
    },
    {
        "boundary": "AFTER_ARTIFACTS_BEFORE_MANIFEST", "acceptedSetCount": 0,
        "manifestLast": True, "realWorktreeUnchanged": True,
        "retryAcceptedSetCount": 1, "retryDeterministic": True,
        "temporaryRootMayContainIncompleteArtifacts": True,
    },
    {
        "boundary": "AFTER_MANIFEST", "acceptedSetCount": 1,
        "manifestLast": True, "realWorktreeUnchanged": True,
        "retryAcceptedSetCount": 1, "retryDeterministic": True,
        "temporaryRootMayContainIncompleteArtifacts": False,
    },
]

assert len(receipt["artifactBindings"]) == 3
assert all(binding_ok(value) for value in receipt["artifactBindings"])
assert tags["observedSuggestions"]["suggestions"] == []
assert tags["observedSuggestions"]["displayGuaranteed"] is False
structured = metadata["structuredData"]
assert structured["customerDataDetected"] is False
assert structured["licensedThirdPartyContentDetected"] is False
assert structured["pairwiseComparisonCount"] == 15
assert structured["canonicalization"] == {
    "originality": "NFKC_LOWERCASE_UNICODE_ALPHANUMERIC_WORD_SET_JACCARD_FLOOR_BASIS_POINTS",
    "originalityDigest": "SORTED_COMPACT_JSON_UTF8_LF_PAGE_CONTENT_COMPARISON",
    "structuredData": "SORTED_COMPACT_JSON_UTF8_LF_HEADLINE_DESCRIPTION_LIMITATIONS",
    "visibleContent": "SORTED_COMPACT_JSON_UTF8_LF_HEADLINE_DESCRIPTION_LIMITATIONS",
}
metadata_bindings = {row["pageID"]: row for row in structured["pageBindings"]}
assert set(metadata_bindings) == {page["pageID"] for page in pages}
for page in pages:
    binding = metadata_bindings[page["pageID"]]
    assert binding == {
        "acceptedFeatureCardID": page["acceptedFeatureCardID"],
        "canonicalURLPath": page["canonicalURLPath"],
        "claimID": page["claimID"],
        "comparedPageContentSHA256s": page["comparedPageContentSHA256s"],
        "maximumPairwiseTokenOverlapBasisPoints": page["maximumPairwiseTokenOverlapBasisPoints"],
        "nearDuplicateThresholdBasisPoints": page["nearDuplicateThresholdBasisPoints"],
        "originalityComparisonSHA256": page["originalityComparisonSHA256"],
        "pageID": page["pageID"],
        "structuredDataSHA256": page["structuredDataSHA256"],
        "visibleContentSHA256": page["visibleContentSHA256"],
    }

assert accessibility["publicationEligible"] is False
assert set(accessibility) == {
    "accessibilityLabelGate", "appStoreSubmission", "appWideAccessibilityLabelAllowed",
    "authority", "c15AccessibilityEvidence", "cardID", "containsLicensedAssets",
    "containsRealCustomerData", "dnsOrHosting", "finalCapture", "networkAccess", "ordinal",
    "provisional", "publicationEligible", "publish", "requiredEvidence", "schema",
    "schemaVersion", "staticOnly", "statusFlags", "supportPages", "syntheticOnly", "upload",
}
assert accessibility["syntheticOnly"] is True
assert accessibility["containsRealCustomerData"] is False
assert accessibility["containsLicensedAssets"] is False
assert accessibility["appWideAccessibilityLabelAllowed"] is False
assert all(accessibility[key] is False for key in (
    "publish", "upload", "networkAccess", "dnsOrHosting",
    "appStoreSubmission", "finalCapture",
))
assert binding_ok(accessibility["c15AccessibilityEvidence"])
gate = accessibility["accessibilityLabelGate"]
assert gate == {
    "status": "REQUIRED_BEFORE_ANY_LABEL",
    "allCommonTaskEvidenceRequired": True,
    "allDeviceFamilyEvidenceRequired": True,
    "physicalEvidenceComplete": False,
    "appWideClaimAllowed": False,
}
assert {
    (page["pageID"], page["canonicalURLPath"]) for page in accessibility["supportPages"]
} == {(page["pageID"], page["canonicalURLPath"]) for page in pages}

assert corpus["schema"] == "V23P04C26OrganicFindabilityCorpusV1"
assert set(corpus) == {
    "authority", "cardID", "containsCustomerData", "containsLicensedAssets", "draftShape",
    "hostileCases", "metadataLimits", "ordinal", "publicationBoundary", "schema",
    "schemaVersion", "selectors", "synthetic", "syntheticAssetScan", "testOnly",
}
assert [row["id"] for row in corpus["selectors"]] == ["G01", "A01", "H01", "I01", "R01"]
assert len(corpus["hostileCases"]) == 12
assert corpus["publicationBoundary"]["status"] == "DISABLED_OR_DEFERRED"
assert all(
    value == 0
    for value in corpus["publicationBoundary"].values()
    if type(value) is int
)
assert set(contract) == {
    "authority", "cardID", "provisional", "schema", "schemaVersion", "semantics",
    "sourceProjection", "statusFlags", "testSelectors",
}
expected_contract_flags = {
    "acceptance", "adoption", "analyticsProvider", "appStoreSubmission", "customerDataUse",
    "dnsHosting", "finalKeywords", "finalScreenshots", "hosted", "native", "networkAccess",
    "paidAcquisition", "publication", "release", "upload",
}
assert set(contract["statusFlags"]) == expected_contract_flags
assert not any(contract["statusFlags"].values())
PY

python3 -B Scripts/v23/generate_p04_c27_contracts.py --check >/dev/null
c27_generator_self_test="$(python3 -B Scripts/v23/generate_p04_c27_contracts.py --self-test --json)"
jq -e '
  .result == "PASS"
  and .protocol == "MANIFEST_LAST_ATOMIC_REPLACE"
  and [.rows[].boundary] == [
    "BEFORE_ARTIFACTS",
    "AFTER_ARTIFACTS_BEFORE_MANIFEST",
    "AFTER_MANIFEST"
  ]
  and [.rows[].acceptedSetCount] == [0, 0, 1]
  and ([.rows[] | (
    .recoveryAcceptedSetCount == 1
    and .secondRetryAcceptedSetCount == 1
    and .recoveryTreeDigest == .secondRetryTreeDigest
  )] | all)
  and ([.rows[].manifestLast] | all(. == true))
  and ([.rows[].retryDeterministic] | all(. == true))
  and ([.rows[].realWorktreeUnchanged] | all(. == true))
  and .deterministicRerun == true
  and .realWorktreeUnchanged == true
' <<<"$c27_generator_self_test" >/dev/null

c27_contract_result="$(python3 -B Scripts/v23/verify_p04_c27_contracts.py --json)"
jq -e '
  .cardID == "V23-P04-C27"
  and .result == "PASS_STATIC_PROVISIONAL"
  and .sourceReady == true
  and .finalHashesSealed == false
  and .flagsAllFalse == true
  and .fencePathCount == 14
  and .existingPathCount == 2
  and .newPathCount == 12
  and .counts.changedPathCount == 14
  and .counts.missingPathCount == 0
  and .counts.unownedChangedPathCount == 0
  and .counts.s10ReservationOverlapCount == 0
  and .selectors == [
    "testV23P04C27G01CompleteBrandHIGStateInventoryAndFreeze",
    "testV23P04C27A01GovernedReuseAndDualRuntimeSemanticParity",
    "testV23P04C27H01HostileIdentityVocabularyStateAndIconDriftFailClosed",
    "testV23P04C27I01ManifestLastInterruptionAndDeterministicRetry",
    "testV23P04C27R01PreflightRemainsProvisionalUntilLaterAuthorities"
  ]
  and (.failures | length) == 0
' <<<"$c27_contract_result" >/dev/null

python3 -B - \
  "$c27_inventory" "$c27_corpus" "$c27_contract" \
  "$c27_evidence" "$c27_impact" "$c27_tooling_manifest" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path.cwd()
inventory, corpus, contract, evidence, impact, manifest = (
    json.loads((root / path).read_bytes()) for path in sys.argv[1:]
)
documents = (inventory, corpus, contract, evidence, impact, manifest)
for document in documents:
    assert document["cardID"] == "V23-P04-C27"
    assert document["schemaVersion"] == 1
    flags = document["statusFlags"]
    assert set(flags) in (
        {"acceptance", "adoption", "hosted", "native", "publication", "release"},
        {"acceptance", "activation", "adoption", "hosted", "native", "physicalDevice", "publication", "release"},
    )
    assert all(value is False for value in flags.values())

assert inventory["schema"] == "V23P04C27BrandHIGStateInventoryV1"
assert inventory["syntheticOnly"] is True
contracts = inventory["contracts"]
assert [contracts[key]["contract"] for key in (
    "brandHIGStateInventory", "applicationStateInventory",
    "brandVocabularyMap", "technicalIdentityFreeze",
)] == [
    "BrandHIGStateInventoryContractV1", "ApplicationStateInventoryV1",
    "BrandVocabularyMapV1", "TechnicalIdentityFreezeV1",
]
assert [contracts[key]["contract"] for key in (
    "affectedConsumerGraph", "brandPrePolishFreezeReceipt", "appIconReleaseManifest",
)] == ["AffectedConsumerGraphV1", "BrandPrePolishFreezeReceiptV1", "AppIconReleaseManifestV1"]
assert contracts["brandPrePolishFreezeReceipt"]["automaticBaselineUpdate"] is False
assert contracts["brandPrePolishFreezeReceipt"]["inFlightExceptionCountFrozen"] is False
assert contracts["technicalIdentityFreeze"]["renameAllowed"] is False
assert all(row["adopted"] is False for row in inventory["discovery"]["c26Drafts"])
for row in inventory["discovery"]["criticalInputs"] + inventory["discovery"]["c26Drafts"]:
    path = pathlib.PurePosixPath(row["path"])
    assert not path.is_absolute() and ".." not in path.parts
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == row["sha256"]

assert contract["provisional"] is True
assert contract["semantics"]["sevenContracts"] == "NONPERSISTENT_INVENTORY_EVIDENCE"
assert contract["semantics"]["newDurableRecordCount"] == 0
assert contract["semantics"]["newDurableFamilies"] == []
assert evidence["generatorInterruptionProtocol"]["protocol"] == "MANIFEST_LAST_ATOMIC_REPLACE"
assert [row["acceptedSetCount"] for row in evidence["generatorInterruptionProtocol"]["rows"]] == [0, 0, 1]
assert impact["uiAdoptionSkipped"] is True and impact["uiAcceptanceCredit"] is False
assert manifest["finalHashesSealed"] is False
assert manifest["counts"] == {
    "changedPathCount": 14,
    "missingPathCount": 0,
    "s10ReservationOverlapCount": 0,
    "unownedChangedPathCount": 0,
}
assert manifest["authority"]["finalHashesSealed"] is False
assert manifest["authority"]["appBaseHead"] == inventory["authority"]["appBaseHead"]
assert manifest["authority"]["appBaseTree"] == inventory["authority"]["appBaseTree"]
assert len(manifest["authority"]["sourcePins"]) == 3
assert manifest["sources"] == contract["sourceProjection"]["sourceRows"]
for row in manifest["files"]:
    assert hashlib.sha256((root / row["path"]).read_bytes()).hexdigest() == row["sha256"]
PY

python -B "$c28_generator_script" --check >/dev/null
c28_generator_self_test="$(python -B "$c28_generator_script" --self-test --json)"
jq -e '
  .result == "PASS"
  and .protocol == "MANIFEST_LAST_ATOMIC_REPLACE"
  and [.rows[].boundary] == [
    "BEFORE_ARTIFACTS",
    "AFTER_ARTIFACTS_BEFORE_MANIFEST",
    "AFTER_MANIFEST"
  ]
  and [.rows[].acceptedSetCount] == [0, 0, 1]
  and ([.rows[] | (
    .recoveryAcceptedSetCount == 1
    and .secondRetryAcceptedSetCount == 1
    and .recoveryTreeDigest == .secondRetryTreeDigest
  )] | all)
  and ([.rows[].manifestLast] | all(. == true))
  and ([.rows[].retryDeterministic] | all(. == true))
  and ([.rows[].realWorktreeUnchanged] | all(. == true))
  and .deterministicRerun == true
  and .realWorktreeUnchanged == true
' <<<"$c28_generator_self_test" >/dev/null

c28_contract_result="$(python -B "$c28_verifier_script" --complete --json)"
c28_fence_path_count="$(jq -er '
  if (.fencePathCount | type) == "number" then .fencePathCount
  elif (.counts.changedPathCount | type) == "number" then .counts.changedPathCount
  else error("C28 verifier omitted a numeric fence path count")
  end
' <<<"$c28_contract_result")"
test "$c28_fence_path_count" -eq "$c28_required_fence_path_count"
jq --argjson fencePathCount "$c28_fence_path_count" -e '
  .cardID == "V23-P04-C28"
  and .result == "PASS_STATIC_PROVISIONAL"
  and .sourceReady == true
  and .finalHashesSealed == false
  and .flagsAllFalse == true
  and ((.fencePathCount // .counts.changedPathCount) == $fencePathCount)
  and (.existingPathCount | type) == "number"
  and (.newPathCount | type) == "number"
  and ((.existingPathCount + .newPathCount) == $fencePathCount)
  and .counts.changedPathCount == $fencePathCount
  and .counts.missingPathCount == 0
  and .counts.unownedChangedPathCount == 0
  and .counts.s10ReservationOverlapCount == 0
  and .selectors == [
    "testV23P04C28G01LowestOwnerCorrectionsCloseC27FindingsAndPreserveHistoricReports",
    "testV23P04C28A01NativeSemanticParityPreservesTasksIdentityAndHistoricBytes",
    "testV23P04C28H01SharedStateRoleAXContrastClaimsAndReportDriftFailClosed",
    "testV23P04C28I01InterruptedCorrectionPreservesAcceptedC27BaselineAndNoPartialReceipt",
    "testV23P04C28R01RejectedDirectionAndFailedRetryPreserveAcceptedBrandRevision"
  ]
  and (.failures | length) == 0
' <<<"$c28_contract_result" >/dev/null

python -B - \
  "$c28_ledger" "$c28_corpus" "$c28_contract" \
  "$c28_evidence" "$c28_impact" "$c28_tooling_manifest" \
  "$c28_schema" "$c27_inventory" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path.cwd()
ledger, corpus, contract, evidence, impact, manifest, schema, c27_inventory = (
    json.loads((root / path).read_bytes()) for path in sys.argv[1:]
)
documents = (ledger, corpus, contract, evidence, impact, manifest)
for document in documents:
    assert document["cardID"] == "V23-P04-C28"
    if "schemaVersion" in document:
        assert document["schemaVersion"] == 1
    flags = document.get("statusFlags", document.get("flags"))
    assert isinstance(flags, dict) and flags
    assert all(value is False for value in flags.values())
    if "provisional" in document:
        assert document["provisional"] is True

assert ledger["schema"] == "V23P04C28BrandHIGSharedRootCorrectionLedgerV1"
assert corpus["schema"] == "V23P04C28BrandHIGSharedRootCorrectionCorpusV1"
assert contract["schema"] == "V23P04C28BrandHIGSharedRootCorrectionToolingV1"
assert contract["contract"] == "BrandHIGSharedRootCorrectionContractV1"
assert evidence["schema"] == "V23P04C28BrandHIGSharedRootCorrectionToolingV1"
assert evidence["receipt"] == "BrandHIGSharedRootCorrectionEvidenceReceiptV1"
assert impact["schema"] == "BrandImpactManifestV1"
assert manifest["schema"] == "V23P04C28ToolingManifestV1"
assert schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema"
assert contract["sourceReady"] is True
assert evidence["sourceReady"] is True

selectors = [
    "testV23P04C28G01LowestOwnerCorrectionsCloseC27FindingsAndPreserveHistoricReports",
    "testV23P04C28A01NativeSemanticParityPreservesTasksIdentityAndHistoricBytes",
    "testV23P04C28H01SharedStateRoleAXContrastClaimsAndReportDriftFailClosed",
    "testV23P04C28I01InterruptedCorrectionPreservesAcceptedC27BaselineAndNoPartialReceipt",
    "testV23P04C28R01RejectedDirectionAndFailedRetryPreserveAcceptedBrandRevision",
]
assert ledger["selectors"] == selectors
assert corpus["selectors"] == selectors
assert contract["selectors"] == selectors
assert evidence["selectors"] == selectors

source_pins = ledger["sourcePins"]
assert set(source_pins) == {
    "acceptedAppHead", "acceptedAppTree", "allocationRevision",
    "c27CheckpointDigest", "c27Inventory", "c27VerificationReceiptDigest",
    "casSequence", "contextDigest", "coordinationAuthorityHead",
    "coordinationAuthorityTree", "coordinationCorrectionTransitionDigest",
    "coordinationLedgerDigest", "frozenS10ReservationDigest",
    "ownerAuthorizedPathAllocationDigest", "pathFenceDigest",
    "provisionalPrerequisiteDigest", "sourceProjectionDigest",
    "supersedesOwnerAuthorizedPathAllocationDigest",
}
assert source_pins["acceptedAppHead"] == "803f75bc94a46b7b0ca50b14f1a49401f38550f1"
assert source_pins["acceptedAppTree"] == "6f1cc0077cf74a1adb532124880b1cd5e4a031cc"
assert source_pins["coordinationAuthorityHead"] == "b30a1640d495bd2d6641ea2dbd816d8d4d23a186"
assert source_pins["coordinationAuthorityTree"] == "f5b3106d41380a906cfa1c0cbf9cdcc8268b4d22"
assert source_pins["casSequence"] == 507
assert source_pins["allocationRevision"] == 2
assert source_pins["ownerAuthorizedPathAllocationDigest"] == "27c242e6c316767b3731c3bda81948ad8a8dc5258b54c385994248c24033f48c"
assert source_pins["supersedesOwnerAuthorizedPathAllocationDigest"] == "f296173b2ae29f892447395bba5d2a48817607375e8da8d3173faf5ff739f3c1"
assert source_pins["contextDigest"] == "1b2bff5c876c8f618dae7015b12d4dd51d431c6756678824d72421b4d55a80a9"
assert source_pins["pathFenceDigest"] == "52a48f30deafc62962e99607f690e84fb393f668c548a01fe496b96b450d3817"
assert source_pins["provisionalPrerequisiteDigest"] == "83888037dd5c9762466f711f232ef5ecad7f34ffce1d773795f10dd8920763ce"
assert source_pins["coordinationCorrectionTransitionDigest"] == "2b610d2031667696ba09337e194c8b42e39e09265fc6245a3f94fdd6271ac294"
assert source_pins["coordinationLedgerDigest"] == "5dd37b9b75422a8366b9e052781d09d022951ed2b3cbe51492765ab58cf2eb5f"
assert source_pins["sourceProjectionDigest"] == "a7064d17aa0bdd7ef1401b411087ff38c64ecefff7a3a9515039aa009d963df5"
assert source_pins["frozenS10ReservationDigest"] == "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
c27_binding = source_pins["c27Inventory"]
assert c27_binding == {
    "path": "docs/product/brand/V23P04C27BrandHIGStateInventoryV1.json",
    "sha256": "b7515c0a7ff3c5e4729605a73e927807524c0d9f51bf400833e4d2d849cdbfc2",
    "utf8Length": 13934,
}
assert hashlib.sha256((root / c27_binding["path"]).read_bytes()).hexdigest() == c27_binding["sha256"]
assert c27_inventory["cardID"] == "V23-P04-C27"

expected_stable = {
    "feedback.mail.attachment-count",
    "feedback.mail.body",
    "feedback.mail.done",
    "feedback.mail.recipient",
    "feedback.mail.screen",
}
receipt = ledger["sharedBrandCorrectionReceipt"]
mappings = receipt["afterSemanticMappings"]
assert {row["stableID"] for row in mappings} == expected_stable
assert all(row["stableID"] != row["legacyID"] for row in mappings)
semantics = corpus["stableFeedbackSemantics"]
assert {row["id"] for row in semantics} == expected_stable
assert all(row["deprecatedAliases"] == [] for row in semantics)
assert {row["id"] for row in corpus["affectedConsumerGraph"]} == expected_stable

legacy_literals = []
for path in (root / "FieldEvidenceApp").rglob("*"):
    if path.is_file() and path.suffix in {".swift", ".json", ".plist", ".xcstrings"}:
        if "s8.4.mail" in path.read_text(encoding="utf-8"):
            legacy_literals.append(path)
assert not legacy_literals, legacy_literals

assert len(ledger["deferredAcceptedS10_6Clusters"]) == 4
assert len(corpus["deferredS10Clusters"]) == 4
assert [row["clusterID"] for row in ledger["deferredAcceptedS10_6Clusters"]] == [
    "all-other-shipping-phase-number-ids-in-S10-reserved-ui-root-paths",
    "visual-DesignTokens-and-WorklightComponents",
    "saved-photo-RecordWork-and-IssueDetail",
    "app-icon-and-artwork",
]
assert [row["clusterID"] for row in corpus["deferredS10Clusters"]] == [
    "all-other-shipping-phase-number-ids-in-S10-reserved-ui-root-paths",
    "visual-DesignTokens-and-WorklightComponents",
    "saved-photo-RecordWork-and-IssueDetail",
    "app-icon-and-artwork",
]
expected_cluster_counts = [18, 2, 2, 4]
expected_cluster_ids = [row["clusterID"] for row in ledger["deferredAcceptedS10_6Clusters"]]
all_member_paths = []
for rows in (ledger["deferredAcceptedS10_6Clusters"], corpus["deferredS10Clusters"]):
    assert [len(row["memberPaths"]) for row in rows] == expected_cluster_counts
    for row, expected_count in zip(rows, expected_cluster_counts):
        assert row["clusterID"] in expected_cluster_ids
        assert row["adopted"] is False
        assert row["disposition"] == "DEFERRED_PENDING_ACCEPTED_S10_6"
        assert row["reservationDigest"] == "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
        paths = [member["path"] for member in row["memberPaths"]]
        assert len(paths) == expected_count and len(paths) == len(set(paths))
        all_member_paths.extend(paths)
assert len(all_member_paths) == len(set(all_member_paths)) * 2
assert all(
    row["adopted"] is False
    and row["disposition"] == "DEFERRED_PENDING_ACCEPTED_S10_6"
    for row in ledger["deferredAcceptedS10_6Clusters"]
)
assert all(
    row["acceptanceCredit"] is False
    and row["disposition"] == "DEFERRED_PENDING_ACCEPTED_S10_6"
    for row in corpus["deferredS10Clusters"]
)

brand_receipt = ledger["brandRevisionImplementationReceipt"]
assert brand_receipt["activated"] is False
assert brand_receipt["authorizedChange"] is False
assert brand_receipt["disposition"] == "NOT_ACTIVATED_NO_APPROVED_DECISION"
icon_receipt = ledger["appIconRevisionReceipt"]
assert icon_receipt["adopted"] is False
assert icon_receipt["authorizedChange"] is False
assert icon_receipt["disposition"] == "NOT_EMITTED_NO_AUTHORIZED_CHANGE"
assert corpus["brandRevisionDisposition"] == "UNCHANGED_NO_ACCEPTED_DIRECTION"
assert corpus["appIconDisposition"] == "NO_CHANGE_NO_ACCEPTED_BRAND_INTENT"

assert ledger["preservation"]["historicReportBytesRewritten"] is False
assert ledger["preservation"]["technicalIdentityChanged"] is False
for binding in corpus["historicReportBindings"]:
    path = pathlib.PurePosixPath(binding["path"])
    assert not path.is_absolute() and ".." not in path.parts
    assert hashlib.sha256((root / path).read_bytes()).hexdigest() == binding["sha256"]

assert ledger["lifecycle"]["persistentKindCount"] == 0
assert ledger["lifecycle"]["writerCount"] == 0
assert ledger["lifecycle"]["workspaceMutationReceiptCreated"] is False
assert corpus["persistentKinds"] == []
assert ledger["candidate"]["sealDisposition"] == "UNSEALED_PROVISIONAL"
assert not any(
    value is True
    for document in documents
    for flags in [document.get("statusFlags", document.get("flags", {}))]
    for value in flags.values()
)
PY

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
