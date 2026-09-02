#!/usr/bin/env python3
"""Generate and fail-close verify the V30 pre-S10 path-fence authority.

This generator is deliberately external to the application repository.  It reads
only the frozen V23 expansion checkout, pins every existing B-tree blob, and
emits a deterministic package artifact.  It never opens C:\\AssetRounds.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


AUTHORITY_ID = "ASSETROUNDS-V30-PRE-S10-20260902-R2"
BASE_BRANCH = "phase/v23-expansion"
BASE_HEAD = "acbfb68355f903fe98638b6ef22e4814e7b48328"
BASE_TREE = "47e17fae6b73dccd5029ccf4ac7cca659196f225"
RESERVATION_RELATIVE_PATH = "docs/design/v23/foundation/ActiveS10OwnershipReservationV1.json"
RESERVATION_RAW_SHA256 = "9f7c27431271728d167731d4af806c7449447dfbcc8bf46778102e2f9a89b576"
RESERVATION_CONTENT_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"
PACKAGE = Path(__file__).resolve().parent
FROZEN_V23 = Path(r"C:\AssetRounds-v23-expansion")
OUTPUT = PACKAGE / "V30_PRE_S10_PATH_FENCES.json"
EXECUTION_ROOT = "docs/design/v30/execution"


def run_git(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(FROZEN_V23), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
    )
    if result.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bytes(path: Path) -> bytes:
    return path.read_bytes()


_FROZEN_TREE_INDEX: dict[str, tuple[str, str]] | None = None
_FROZEN_BLOB_CACHE: dict[str, tuple[str, str]] = {}


def frozen_tree_index() -> dict[str, tuple[str, str]]:
    """Index the exact B tree once; every subsequent fence check uses it."""
    global _FROZEN_TREE_INDEX
    if _FROZEN_TREE_INDEX is not None:
        return _FROZEN_TREE_INDEX
    index: dict[str, tuple[str, str]] = {}
    for line in run_git("ls-tree", "-r", BASE_HEAD).splitlines():
        metadata, path = line.split("\t", maxsplit=1)
        mode, kind, blob_oid = metadata.split()
        if kind != "blob":
            continue
        index[path] = (mode, blob_oid)
    _FROZEN_TREE_INDEX = index
    return index


def frozen_blob(path: str) -> tuple[str, str]:
    """Return the exact B-tree blob OID and raw blob SHA-256 for an existing path."""
    if path in _FROZEN_BLOB_CACHE:
        return _FROZEN_BLOB_CACHE[path]
    record = frozen_tree_index().get(path)
    if record is None:
        raise RuntimeError(f"expected frozen-B existing path is absent: {path}")
    _, blob_oid = record
    raw = subprocess.run(
        ["git", "-C", str(FROZEN_V23), "cat-file", "-p", blob_oid],
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    value = (blob_oid, sha256(raw))
    _FROZEN_BLOB_CACHE[path] = value
    return value


def assert_absent_at_b(path: str) -> None:
    if path in frozen_tree_index():
        raise RuntimeError(f"expected B-absent path already exists: {path}")


def expected_absent(path: str, purpose: str, *, shared: bool = False) -> dict[str, Any]:
    return {
        "classification": "EXPECTED_ABSENT_NEW_PATH",
        "expectedBBlobOID": None,
        "expectedBSHA256": None,
        "path": path,
        "purpose": purpose,
        "serializedSharedPath": shared,
    }


def existing(path: str, purpose: str, *, shared: bool = False) -> dict[str, Any]:
    oid, digest = frozen_blob(path)
    return {
        "classification": "EXISTING_BLOB",
        "expectedBBlobOID": oid,
        "expectedBSHA256": digest,
        "path": path,
        "purpose": purpose,
        "serializedSharedPath": shared,
    }


# These are the only V30 transition records shared by pre-S10 executable cards.
# The ledger-named file is strictly a read-only/current-tip projection of the
# isolated external coordination ledger; it is not a second canonical ledger.
# The records are included in every executable card's fence so transition and
# checkpoint mutation is explicit, and the writer order is closed at C37.
EXECUTABLE_CARD_IDS = [
    f"V30-P{phase:02d}-C{card:02d}"
    for phase, card, maximum in ((0, 1, 6), (1, 1, 8), (2, 1, 7), (3, 1, 9), (4, 1, 7))
    for card in range(1, maximum + 1)
]
SHARED_EXECUTION_PATHS: dict[str, str] = {
    f"{EXECUTION_ROOT}/V30_CURRENT_TASK.md": "Single selected-card projection; transition only after the current card's provisional checkpoint.",
    f"{EXECUTION_ROOT}/V30_CI_SELECTION.json": "V30-only provisional selector projection; never the inherited Scripts/ci-selection.json.",
    f"{EXECUTION_ROOT}/V30_PROVISIONAL_LEDGER_PROJECTION.json": "Read-only/current-tip projection of the isolated external provisional coordination ledger; never a canonical ledger.",
    f"{EXECUTION_ROOT}/V30_EXECUTION_HANDOFF.md": "Append-only V30 provisional handoff evidence.",
}


def common_execution_paths() -> list[dict[str, Any]]:
    return [
        expected_absent(path, purpose, shared=True)
        for path, purpose in SHARED_EXECUTION_PATHS.items()
    ]


def n(path: str, purpose: str) -> tuple[str, str, str]:
    return ("NEW", path, purpose)


def e(path: str, purpose: str) -> tuple[str, str, str]:
    return ("EXISTING", path, purpose)


# The static list is the authorization surface.  It uses one card-exclusive V30
# source/test/document lane per card wherever possible.  The sole frozen-B
# production surface is Localizable.xcstrings in C15; it is not S10-reserved.
CARD_SPECS: list[dict[str, Any]] = [
    {
        "ordinal": 1,
        "cardID": "V30-P00-C01",
        "title": "Provisional authority and isolated-lane validation",
        "class": "FOUNDATION",
        "directPrerequisites": [],
        "paths": [
            n(f"{EXECUTION_ROOT}/V30_PROVISIONAL_ACTIVATION_RECEIPT.json", "Record external-authority installation validation without modifying immutable authority artifacts."),
            n(f"{EXECUTION_ROOT}/contexts/V30-P00-C01-attempt-1.json", "Card 1 immutable observed-context projection."),
            n(f"{EXECUTION_ROOT}/receipts/V30-P00-C01-validation-receipt.json", "Card 1 fail-closed validation receipt."),
        ],
    },
    {
        "ordinal": 2,
        "cardID": "V30-P00-C02",
        "title": "Frozen V23/S10 reservation and provisional-fence proof",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P00-C01"],
        "paths": [
            n(f"{EXECUTION_ROOT}/contexts/V30-P00-C02-attempt-1.json", "Immutable V23/S10 observation context."),
            n(f"{EXECUTION_ROOT}/proofs/V30-P00-C02-reservation-and-fence-proof.json", "Ordered reservation and path-classification proof."),
            n(f"{EXECUTION_ROOT}/receipts/V30-P00-C02-fence-proof-receipt.json", "Card 2 provisional proof receipt."),
        ],
    },
    {
        "ordinal": 3,
        "cardID": "V30-P00-C03",
        "title": "Namespaced provisional coordination genesis validation",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P00-C01", "V30-P00-C02"],
        "paths": [
            n(f"{EXECUTION_ROOT}/V30_PROVISIONAL_COORDINATION_GENESIS.json", "Sole G3-created isolated coordination genesis record."),
            n(f"{EXECUTION_ROOT}/contexts/V30-P00-C03-attempt-1.json", "Card 3 ledger-genesis validation context."),
            n(f"{EXECUTION_ROOT}/receipts/V30-P00-C03-genesis-validation-receipt.json", "Schema-sealed genesis validation receipt."),
        ],
    },
    {
        "ordinal": 4,
        "cardID": "V30-P00-C04",
        "title": "Provisional candidate and reconciliation-manifest contract",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P00-C02", "V30-P00-C03"],
        "paths": [
            n("docs/design/v30/contracts/V30ProvisionalCandidateReconciliationManifestV1.json", "B/P/S candidate and replay contract."),
            n("docs/design/v30/schemas/v30-provisional-candidate-reconciliation-manifest.schema.json", "Schema for per-card candidate/reconciliation manifests."),
            n("Scripts/v30/validate_v30_provisional_candidate_manifest.py", "Deterministic V30 candidate-manifest validator."),
            n("FieldEvidenceAppTests/V30_P00_C04CandidateReconciliationManifestTests.swift", "Contract tests for B/P/S candidate mappings."),
        ],
    },
    {
        "ordinal": 5,
        "cardID": "V30-P00-C05",
        "title": "Provisional CI and checkpoint contract",
        "class": "VERIFICATION",
        "directPrerequisites": ["V30-P00-C03", "V30-P00-C04"],
        "paths": [
            e(".github/workflows/ios-ci.yml", "Change only the phase/v30-globalization branch copy to consume docs/design/v30/execution/V30_CI_SELECTION.json typed selector; preserve pinned runner/toolchain/simulator/watchdogs/evidence/commands, route/ref isolation, and no main or Phase10 mutation."),
            e("Scripts/test-smoke.sh", "Change only the phase/v30-globalization branch copy to consume docs/design/v30/execution/V30_CI_SELECTION.json typed selector; preserve pinned test commands, watchdogs, evidence, route/ref isolation, and no main or Phase10 mutation."),
            e("Scripts/ui-smoke.sh", "Change only the phase/v30-globalization branch copy to consume docs/design/v30/execution/V30_CI_SELECTION.json typed selector; preserve pinned UI commands, watchdogs, evidence, route/ref isolation, and no main or Phase10 mutation."),
            n("docs/design/v30/contracts/V30ProvisionalCIAndCheckpointContractV1.json", "Pinned provisional development-route and checkpoint contract."),
            n(f"{EXECUTION_ROOT}/V30_PROVISIONAL_DEVELOPMENT_ROUTE_SELECTOR.json", "V30-only route selector; never active S10 CI configuration."),
            n("Scripts/v30/validate_v30_provisional_ci_contract.py", "Deterministic provisional CI-contract validator."),
            n("FieldEvidenceAppTests/V30_P00_C05ProvisionalCheckpointContractTests.swift", "Checkpoint contract unit evidence."),
        ],
    },
    {
        "ordinal": 6,
        "cardID": "V30-P00-C06",
        "title": "Provisional execution admission",
        "class": "INTEGRATION",
        "directPrerequisites": ["V30-P00-C04", "V30-P00-C05"],
        "paths": [
            n(f"{EXECUTION_ROOT}/V30_PROVISIONAL_ADMISSION_CAS.json", "Separate provisional admission CAS record."),
            n(f"{EXECUTION_ROOT}/receipts/V30-P00-C06-admission-receipt.json", "Admission receipt proving P05-P07 remain unselectable."),
            n("docs/design/v30/contracts/V30PreS10SelectabilityProjectionV1.json", "Closed pre-S10 selectability projection."),
        ],
    },
    {
        "ordinal": 7,
        "cardID": "V30-P01-C01",
        "title": "Research manifest and initial-language confirmation",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P00-C06"],
        "paths": [
            n("docs/design/v30/research/V30ResearchManifestV1.json", "Pinned source/research manifest and six-locale confirmation."),
            n("docs/design/v30/research/V30InitialLanguageCohortV1.json", "U.S. initial-language cohort decision record."),
            n("docs/design/v30/research/V30CompetitorCapabilityEvidenceV1.json", "Competitor declaration/review evidence normalization."),
            n("FieldEvidenceAppTests/V30_P01_C01ResearchCohortTests.swift", "Cohort and source-manifest validation."),
        ],
    },
    {
        "ordinal": 8,
        "cardID": "V30-P01-C02",
        "title": "Customer-needs and scope-disposition register",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P01-C01"],
        "paths": [
            n("docs/design/v30/research/V30CustomerNeedsScopeDispositionRegisterV1.json", "Bounded customer-need disposition register."),
            n("docs/design/v30/research/V30KeywordEvidenceBindingV1.json", "Verified keyword-package binding and non-authorizing disposition."),
            n("FieldEvidenceAppTests/V30_P01_C02ScopeDispositionTests.swift", "Scope-disposition invariants."),
        ],
    },
    {
        "ordinal": 9,
        "cardID": "V30-P01-C03",
        "title": "Complete text-bearing surface inventory",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P01-C02"],
        "paths": [
            n("docs/design/v30/inventory/V30TextBearingSurfaceInventoryV1.json", "Exhaustive owned text-bearing surface inventory."),
            n("docs/design/v30/inventory/V30TextSurfaceDispositionSchemaV1.json", "Schema for owner/disposition records."),
            n("Scripts/v30/validate_v30_text_surface_inventory.py", "Inventory coverage and ownership validator."),
            n("FieldEvidenceAppTests/V30_P01_C03TextSurfaceInventoryTests.swift", "Text-surface inventory evidence."),
        ],
    },
    {
        "ordinal": 10,
        "cardID": "V30-P01-C04",
        "title": "Language, locale, content, report, storefront, and jurisdiction contracts",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C01"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/GlobalizationAxisContractsV1.swift", "Independent BCP-47, formatting, zone, calendar, content, report, storefront, and jurisdiction contracts."),
            n("FieldEvidenceApp/Application/Globalization/GlobalizationAxisCoordinatorV1.swift", "Axis resolution coordinator without a parallel framework."),
            n("FieldEvidenceAppTests/V30_P01_C04GlobalizationAxisContractTests.swift", "Six-axis independence and canonical-value tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/GlobalizationAxes/axis-matrix-v1.json", "Deterministic axis-matrix fixture."),
        ],
    },
    {
        "ordinal": 11,
        "cardID": "V30-P01-C05",
        "title": "Canonical-data and historical-identity invariance",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C04"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/CanonicalIdentityInvarianceV1.swift", "Language/locale invariance assertions for canonical identity."),
            n("FieldEvidenceApp/Application/Globalization/CanonicalIdentityAuditCoordinatorV1.swift", "Audit coordinator for journals, evidence, backup, and jurisdiction invariance."),
            n("FieldEvidenceAppTests/V30_P01_C05CanonicalIdentityInvarianceTests.swift", "Canonical-ID and historical identity regression tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/CanonicalIdentity/en-us-identity-baseline-v1.json", "Frozen en-US identity baseline fixture."),
        ],
    },
    {
        "ordinal": 12,
        "cardID": "V30-P01-C06",
        "title": "System-first resolution, fallback, and effective-language evidence",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C03", "V30-P01-C04"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/EffectiveLanguageContractsV1.swift", "System-first effective-language and fallback contracts."),
            n("FieldEvidenceApp/Infrastructure/Localization/SystemLanguageResolverV1.swift", "Apple locale/per-app resolution adapter without bundle swizzling."),
            n("FieldEvidenceApp/Application/Settings/GlobalizationSettingsCoordinatorV1.swift", "Safe Settings handoff and foreground/relaunch coordinator."),
            n("FieldEvidenceAppTests/V30_P01_C06SystemLanguageResolutionTests.swift", "Exact/base/English fallback and raw-key prevention tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/LanguageResolution/system-language-cases-v1.json", "Deterministic system-language resolution fixtures."),
        ],
    },
    {
        "ordinal": 13,
        "cardID": "V30-P01-C07",
        "title": "Locale-aware formatting and input grammar",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C04", "V30-P01-C05"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/LocaleFormatContractsV1.swift", "Locale formatting and canonical-input grammar contracts."),
            n("FieldEvidenceApp/Infrastructure/Localization/LocaleFormattingServiceV1.swift", "Foundation-backed date/number/unit/phone/address formatter and parser."),
            n("FieldEvidenceAppTests/V30_P01_C07LocaleFormattingTests.swift", "DST, calendar, number, unit, paper, parsing, and canonical round-trip tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/LocaleFormatting/formatting-grammar-cases-v1.json", "Locale-hostile input grammar fixtures."),
        ],
    },
    {
        "ordinal": 14,
        "cardID": "V30-P01-C08",
        "title": "Catalog release mechanism, provenance schema, compatibility, and offline integrity",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C03", "V30-P01-C04", "V30-P01-C05", "V30-P01-C06"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/LocalizationCatalogReleaseContractsV1.swift", "Versioned catalog release, compatibility, supersession, rollback, and provenance contracts."),
            n("FieldEvidenceApp/Infrastructure/Localization/LocalizationCatalogReleaseStoreV1.swift", "Offline catalog release storage and historical lookup."),
            n("FieldEvidenceAppTests/V30_P01_C08CatalogReleaseIntegrityTests.swift", "Offline integrity and historical lookup tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/CatalogRelease/catalog-release-cases-v1.json", "Catalog release compatibility fixtures."),
        ],
    },
    {
        "ordinal": 15,
        "cardID": "V30-P02-C01",
        "title": "English catalog normalization",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C03", "V30-P01-C08"],
        "paths": [
            e("FieldEvidenceApp/Resources/Localizable.xcstrings", "Normalize app-owned English semantic keys, comments, placeholders, plurals, and literal dispositions."),
            n("FieldEvidenceApp/Infrastructure/Localization/V30EnglishCatalogRegistryV1.swift", "Typed V30 English catalog registry and semantic-key policy."),
            n("FieldEvidenceAppTests/V30_P02_C01EnglishCatalogNormalizationTests.swift", "English semantic-key, placeholder, plural, and literal-disposition tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/EnglishCatalog/english-catalog-audit-v1.json", "English catalog audit fixture."),
        ],
    },
    {
        "ordinal": 16,
        "cardID": "V30-P02-C02",
        "title": "Unicode input, persistence, journal, and evidence safety",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C05"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/UnicodeEvidenceSafetyContractsV1.swift", "Unicode preservation and spoof-safe display contracts."),
            n("FieldEvidenceApp/Application/Globalization/UnicodeEvidenceSafetyCoordinatorV1.swift", "Boundary audit coordinator for persistence, journal, backup, restore, and erase."),
            n("FieldEvidenceAppTests/V30_P02_C02UnicodeEvidenceSafetyTests.swift", "Grapheme, CJK, emoji, bidi, filename, and evidence-preservation tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Unicode/unicode-evidence-hostile-cases-v1.json", "Hostile Unicode preservation fixtures."),
        ],
    },
    {
        "ordinal": 17,
        "cardID": "V30-P02-C03",
        "title": "RTL and bidirectional semantics",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C06", "V30-P02-C02"],
        "paths": [
            n("FieldEvidenceApp/Infrastructure/Localization/BidirectionalTextSafetyV1.swift", "Bidirectional rendering, isolation, and mixed-identifier safety policy."),
            n("FieldEvidenceApp/Features/Globalization/GlobalizationRTLSemanticsV1.swift", "Semantic mirroring/focus/navigation rendering helper."),
            n("FieldEvidenceAppTests/V30_P02_C03RTLSemanticsTests.swift", "RTL layout, mixed direction, and invisible-control safety tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/RTL/rtl-hostile-cases-v1.json", "Arabic/bidi hostile fixtures without Arabic-shipping claim."),
        ],
    },
    {
        "ordinal": 18,
        "cardID": "V30-P02-C04",
        "title": "Expansion, Dynamic Type, accessibility, and font policy",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P02-C01", "V30-P02-C03"],
        "paths": [
            n("FieldEvidenceApp/DesignSystem/GlobalizationAdaptiveLayoutPolicyV1.swift", "Expansion, Dynamic Type, font fallback, touch-target, contrast, and focus policy."),
            n("FieldEvidenceApp/Features/Globalization/GlobalizationAccessibilityPolicyV1.swift", "Localized accessibility and long-text surface policy."),
            n("FieldEvidenceAppTests/V30_P02_C04AdaptiveAccessibilityTests.swift", "Dynamic Type, expansion, VoiceOver, and font-policy tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Accessibility/expansion-and-type-cases-v1.json", "Long-text and accessibility-size fixtures."),
        ],
    },
    {
        "ordinal": 19,
        "cardID": "V30-P02-C05",
        "title": "Locale-aware search, sorting, and normalization",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C07", "V30-P02-C02"],
        "paths": [
            n("FieldEvidenceApp/Domain/Search/GlobalizedSearchNormalizationContractsV1.swift", "Versioned derived-search normalization and stable tie-breaker contracts."),
            n("FieldEvidenceApp/Infrastructure/Search/GlobalizedSearchNormalizationServiceV1.swift", "CJK, Hangul, diacritic, Turkish, and Arabic normalization adapter."),
            n("FieldEvidenceAppTests/V30_P02_C05GlobalizedSearchTests.swift", "Search rebuild, recovery, erase, backup, and canonical-identifier tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Search/globalized-search-cases-v1.json", "Locale-aware search and sorting fixtures."),
        ],
    },
    {
        "ordinal": 20,
        "cardID": "V30-P02-C06",
        "title": "Pseudo, RTL, long-text, and screenshot harness",
        "class": "VERIFICATION",
        "directPrerequisites": ["V30-P02-C03", "V30-P02-C04", "V30-P02-C05"],
        "paths": [
            n("FieldEvidenceAppTests/TestSupport/V30PseudoLocalizationHarnessV1.swift", "Deterministic pseudo/RTL/long-text nonproduction test harness."),
            n("FieldEvidenceAppTests/V30_P02_C06PseudoLocalizationHarnessTests.swift", "Unresolved-key and fallback-counter harness tests."),
            n("FieldEvidenceAppUITests/V30_P02_C06PseudoLocalizationUITests.swift", "Provisional screenshot/Dynamic Type UI harness tests."),
            n("FieldEvidenceAppUITests/Fixtures/V30/PseudoLocalization/pseudo-locale-screenshot-matrix-v1.json", "Screenshot/device/type matrix fixture."),
            n("docs/design/v30/verification/V30P02C06ProvisionalScreenshotHarnessContractV1.json", "Provisional-only screenshot harness contract."),
        ],
    },
    {
        "ordinal": 21,
        "cardID": "V30-P02-C07",
        "title": "Language & Region Settings and report-language controls",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C06", "V30-P01-C07", "V30-P02-C04"],
        "paths": [
            n("FieldEvidenceApp/Features/Settings/GlobalizationSettingsViewV1.swift", "Localized effective-language/region and report-language settings view."),
            n("FieldEvidenceApp/Domain/Reporting/ReportLanguageContractsV1.swift", "Independent report-language selection contracts."),
            n("FieldEvidenceApp/Application/Reporting/ReportLanguageCoordinatorV1.swift", "Report-language and jurisdiction disclosure coordinator."),
            n("FieldEvidenceAppTests/V30_P02_C07LanguageRegionSettingsTests.swift", "Language, region, report-language, and jurisdiction-separation tests."),
        ],
    },
    {
        "ordinal": 22,
        "cardID": "V30-P03-C01",
        "title": "Authored-content and template-language model",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C04", "V30-P02-C02"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/AuthoredContentLanguageContractsV1.swift", "App/UI/template/evidence/derived-translation/report-chrome content-language distinctions."),
            n("FieldEvidenceApp/Application/Globalization/AuthoredContentLanguageCoordinatorV1.swift", "Source preservation and derived-translation invalidation coordinator."),
            n("FieldEvidenceAppTests/V30_P03_C01AuthoredContentLanguageTests.swift", "Edit/redaction/source/derived-language lifecycle tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/AuthoredContent/authored-content-language-cases-v1.json", "Authored-content language fixtures."),
        ],
    },
    {
        "ordinal": 23,
        "cardID": "V30-P03-C02",
        "title": "Offline and sync-state localization integrity",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C08", "V30-P02-C04"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/LocalizedSyncStateContractsV1.swift", "Existing sync state localization truth contracts."),
            n("FieldEvidenceApp/Infrastructure/Localization/LocalizedSyncStateRendererV1.swift", "Pending/saved/syncing/failed/conflict/recovery localization renderer."),
            n("FieldEvidenceAppTests/V30_P03_C02OfflineSyncLocalizationTests.swift", "Offline startup, Unicode attachment, recovery, and notification truth tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/SyncStates/localized-sync-state-cases-v1.json", "Existing sync-state locale fixtures."),
        ],
    },
    {
        "ordinal": 24,
        "cardID": "V30-P03-C03",
        "title": "Forms, required-state, validation, and conditional semantics",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C07", "V30-P02-C04", "V30-P03-C01"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/LocalizedFormSemanticsContractsV1.swift", "Localized form label/required/optional/error/condition contracts preserving canonical rules."),
            n("FieldEvidenceApp/Application/Globalization/LocalizedFormSemanticsCoordinatorV1.swift", "Form semantic resolution coordinator."),
            n("FieldEvidenceAppTests/V30_P03_C03LocalizedFormSemanticsTests.swift", "Required-state, choice-order, unit, numeral, and conditional-rule tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Forms/localized-form-semantics-cases-v1.json", "Localized form semantic fixtures."),
        ],
    },
    {
        "ordinal": 25,
        "cardID": "V30-P03-C04",
        "title": "Unicode PDF and accessible-document renderer",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C07", "V30-P02-C04", "V30-P03-C01"],
        "paths": [
            n("FieldEvidenceApp/Domain/Reporting/GlobalizedAccessibleDocumentContractsV1.swift", "Unicode/PDF/document language/font/paper/provenance contracts."),
            n("FieldEvidenceApp/Infrastructure/Reporting/GlobalizedAccessibleDocumentRendererV1.swift", "Unicode shaping, font, Letter/A4, semantic-order, and replay renderer."),
            n("FieldEvidenceAppTests/V30_P03_C04GlobalizedAccessibleDocumentTests.swift", "CJK/RTL extraction, font, paper, association, and replay tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Reports/globalized-accessible-document-cases-v1.json", "Report rendering/extraction fixtures."),
        ],
    },
    {
        "ordinal": 26,
        "cardID": "V30-P03-C05",
        "title": "Stable JSON, CSV, export, and import contracts",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C05", "V30-P03-C01"],
        "paths": [
            n("FieldEvidenceApp/Domain/ImportExport/GlobalizedMachineExportContractsV1.swift", "Language-neutral machine export/import and localized-human variant contracts."),
            n("FieldEvidenceApp/Infrastructure/ImportExport/GlobalizedMachineExportAdapterV1.swift", "Locale manifests, formula safety, media references, and canonical round-trip adapter."),
            n("FieldEvidenceAppTests/V30_P03_C05GlobalizedMachineExportTests.swift", "JSON/CSV/import stable-key and exact round-trip tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/ImportExport/globalized-machine-export-cases-v1.json", "Export/import locale-manifest fixtures."),
        ],
    },
    {
        "ordinal": 27,
        "cardID": "V30-P03-C06",
        "title": "Share, email, print, and label surfaces",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P02-C04", "V30-P03-C04"],
        "paths": [
            n("FieldEvidenceApp/Features/Globalization/GlobalizedSharePrintLabelSurfacesV1.swift", "Share/email/print/label chrome and explicit document-language surfaces."),
            n("FieldEvidenceApp/Application/Reporting/GlobalizedShareDeliveryCoordinatorV1.swift", "Localized subject/body/summary delivery coordinator."),
            n("FieldEvidenceAppTests/V30_P03_C06SharePrintLabelTests.swift", "Share, email, print, label, and authored-content preservation tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Share/globalized-share-print-label-cases-v1.json", "Share/print/label fixtures."),
        ],
    },
    {
        "ordinal": 28,
        "cardID": "V30-P03-C07",
        "title": "OCR, dictation, speech, and assisted-input capability truth",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C06", "V30-P03-C01"],
        "paths": [
            n("FieldEvidenceApp/Domain/Globalization/AssistedInputCapabilityContractsV1.swift", "Per-locale OS/device/build capability truth contracts."),
            n("FieldEvidenceApp/Application/Globalization/AssistedInputCapabilityCoordinatorV1.swift", "Truthful OCR/dictation/speech capability resolver."),
            n("FieldEvidenceAppTests/V30_P03_C07AssistedInputCapabilityTests.swift", "Unavailable capability and translated-label truth tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/AssistedInput/assisted-input-capability-cases-v1.json", "Per-locale capability matrix fixtures."),
        ],
    },
    {
        "ordinal": 29,
        "cardID": "V30-P03-C08",
        "title": "Backup, restore, and historical catalog replay",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C08", "V30-P03-C04", "V30-P03-C05"],
        "paths": [
            n("FieldEvidenceApp/Domain/Backup/GlobalizedCatalogReplayContractsV1.swift", "Catalog/font/renderer/source/replay/missing-resource backup contracts."),
            n("FieldEvidenceApp/Infrastructure/Backup/GlobalizedCatalogReplayAdapterV1.swift", "Historical catalog/replay and explicit limitation adapter."),
            n("FieldEvidenceAppTests/V30_P03_C08GlobalizedCatalogReplayTests.swift", "Restore/replay/search-rebuild/current-language independence tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/Backup/globalized-catalog-replay-cases-v1.json", "Backup/restore catalog replay fixtures."),
        ],
    },
    {
        "ordinal": 30,
        "cardID": "V30-P03-C09",
        "title": "Onboarding, help, errors, permissions, notifications, support, and destructive actions",
        "class": "IMPLEMENTATION",
        "directPrerequisites": ["V30-P01-C06", "V30-P02-C04", "V30-P03-C02"],
        "paths": [
            n("FieldEvidenceApp/Features/Globalization/CriticalSurfaceLocalizationRegistryV1.swift", "Critical onboarding/help/error/permission/notification/support/destructive surface registry."),
            n("FieldEvidenceApp/Application/Globalization/CriticalSurfaceRecoveryCoordinatorV1.swift", "Contextual recovery and deep-link consistency coordinator."),
            n("FieldEvidenceAppTests/V30_P03_C09CriticalSurfaceLocalizationTests.swift", "Critical surface and hidden-English regression tests."),
            n("FieldEvidenceAppTests/Fixtures/V30/CriticalSurfaces/critical-surface-cases-v1.json", "Critical localization/recovery fixtures."),
        ],
    },
    {
        "ordinal": 31,
        "cardID": "V30-P04-C01",
        "title": "Termbase, do-not-translate list, and secure review workflow",
        "class": "FOUNDATION",
        "directPrerequisites": ["V30-P02-C06", "V30-P03-C03", "V30-P03-C04", "V30-P03-C05", "V30-P03-C06", "V30-P03-C09"],
        "paths": [
            n("docs/design/v30/translation/V30TermbaseV1.json", "Concept IDs, U.S. field terminology, and do-not-translate list."),
            n("docs/design/v30/translation/V30SecureLinguisticReviewWorkflowV1.json", "Minimal-access reviewer workflow, roles, corrections, and supersession."),
            n("docs/design/v30/translation/V30TranslationReviewPacketSchemaV1.json", "Versioned review packet schema."),
            n("Scripts/v30/validate_v30_translation_review_packet.py", "Termbase and review-packet validator."),
            n("FieldEvidenceAppTests/V30_P04_C01TranslationWorkflowTests.swift", "Termbase/review workflow contract tests."),
        ],
    },
]


LOCALE_CARDS = [
    (32, "V30-P04-C02", "U.S. Spanish", "es", "Spanish"),
    (33, "V30-P04-C03", "Simplified Chinese", "zh-Hans", "SimplifiedChinese"),
    (34, "V30-P04-C04", "Traditional Chinese", "zh-Hant", "TraditionalChinese"),
    (35, "V30-P04-C05", "Vietnamese", "vi", "Vietnamese"),
    (36, "V30-P04-C06", "Korean", "ko", "Korean"),
]
for ordinal, card_id, title, locale, test_stem in LOCALE_CARDS:
    CARD_SPECS.append(
        {
            "ordinal": ordinal,
            "cardID": card_id,
            "title": title,
            "class": "IMPLEMENTATION",
            "directPrerequisites": ["V30-P04-C01"],
            "paths": [
                n(f"FieldEvidenceApp/Resources/Globalization/{locale}.app.json", f"Locale-exclusive {locale} app-owned catalog."),
                n(f"FieldEvidenceApp/Resources/Globalization/{locale}.report.json", f"Locale-exclusive {locale} report chrome catalog."),
                n(f"FieldEvidenceApp/Resources/Globalization/{locale}.accessibility.json", f"Locale-exclusive {locale} accessibility/permission/error catalog."),
                n(f"FieldEvidenceAppTests/Fixtures/V30/Locales/{locale}.json", f"Locale-exclusive {locale} fixture corpus."),
                n(f"FieldEvidenceAppTests/V30_P04_C{ordinal - 30:02d}{test_stem}LocalizationTests.swift", f"{locale} locale implementation tests."),
                n(f"docs/design/v30/locales/{locale}/V30P04C{ordinal - 30:02d}ReviewPacketV1.json", f"{locale} provisional review packet."),
            ],
        }
    )

# C37 receives the sole owner-authorized S10 overlap tuple below.  Its one
# reserved project metadata change is limited to locale resource membership;
# it does not admit Phase10-owned settings or any other UI/brand path.
CARD_SPECS.append(
    {
        "ordinal": 37,
        "cardID": "V30-P04-C07",
        "title": "Shared catalog, Xcode project, and provisional locale-release integration",
        "class": "INTEGRATION",
        "directPrerequisites": [
            "V30-P02-C07",
            "V30-P03-C08",
            "V30-P04-C02",
            "V30-P04-C03",
            "V30-P04-C04",
            "V30-P04-C05",
            "V30-P04-C06",
        ],
        "paths": [
            e("FieldEvidenceApp.xcodeproj/project.pbxproj", "Add only V30 localization known-region/resource membership required for six locales; preserve Phase10-owned settings."),
            n("docs/design/v30/translation/V30ProvisionalLocalizationCatalogReleaseV1.json", "Complete provisional six-locale catalog-release record."),
            n(f"{EXECUTION_ROOT}/receipts/V30-P04-C07-provisional-integration-receipt.json", "Card 37 locale-release integration receipt."),
            n("docs/design/v30/verification/V30P04C07LocaleIntegrationMatrixV1.json", "Six-locale membership and lane-isolation matrix."),
            n("FieldEvidenceAppTests/V30_P04_C07LocaleReleaseIntegrationTests.swift", "Provisional shared catalog/project integration tests."),
        ],
    }
)


# Frozen-B SwiftUI literal inventory.  These 47 concrete files were identified
# before any V30 mutation from Text/Label/Button/Toggle/Picker/Section/
# TextField/SecureField/LabeledContent/ContentUnavailableView/ShareLink/Menu/
# NavigationLink/navigationTitle/alert/confirmationDialog/accessibility literal
# calls.  C15 owns semantic-key conversion and explicit literal disposition;
# later cards own only their separately fenced behavioral/layout deltas.
UI_LITERAL_OWNER_PATHS = [
    "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
    "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
    "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
    "FieldEvidenceApp/Features/Issues/IssueDetailView.swift",
    "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
    "FieldEvidenceApp/Features/Reports/ReportCorrectionView.swift",
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
    "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
    "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
    "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
    "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
    "FieldEvidenceApp/Features/Signs/NewSignView.swift",
    "FieldEvidenceApp/Features/Signs/SignDetailView.swift",
    "FieldEvidenceApp/Features/Signs/SignsRootView.swift",
    "FieldEvidenceApp/Features/Subscription/PaywallView.swift",
    "FieldEvidenceApp/Features/Subscription/SubscriptionStatusView.swift",
    "FieldEvidenceApp/Features/Accountability/SignoffEnrollmentView.swift",
    "FieldEvidenceApp/Features/Activities/InstallationWorkflowView.swift",
    "FieldEvidenceApp/Features/Activities/PunchReviewWorkflowView.swift",
    "FieldEvidenceApp/Features/AssetImport/PartyContactSiteRoleImportView.swift",
    "FieldEvidenceApp/Features/CheckRunner/EvidenceCurationView.swift",
    "FieldEvidenceApp/Features/CheckRunner/EvidenceQualityCoachView.swift",
    "FieldEvidenceApp/Features/Contacts/OperationalContactHandoffView.swift",
    "FieldEvidenceApp/Features/Contacts/PartyContactSiteRoleWorkflowView.swift",
    "FieldEvidenceApp/Features/Dashboard/ExceptionReviewQueueView.swift",
    "FieldEvidenceApp/Features/Dashboard/OperationsDashboardView.swift",
    "FieldEvidenceApp/Features/Integrations/IncumbentFileAdapterWorkflowView.swift",
    "FieldEvidenceApp/Features/MyDay/MyDayWorkflowView.swift",
    "FieldEvidenceApp/Features/PartsStock/PartsStockWorkflowView.swift",
    "FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift",
    "FieldEvidenceApp/Features/ReviewExchange/RecipientReviewWorkflowView.swift",
    "FieldEvidenceApp/Features/Rounds/OfflineReadinessPreflightView.swift",
    "FieldEvidenceApp/Features/Rounds/RoundSessionView.swift",
    "FieldEvidenceApp/Features/Scheduling/AdvancedRecurrenceWorkflowView.swift",
    "FieldEvidenceApp/Features/ServiceRequests/ServiceRequestWorkflowView.swift",
    "FieldEvidenceApp/Features/Settings/RatingSupportWorkflowView.swift",
    "FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift",
    "FieldEvidenceApp/Features/WorkResources/ManualWorkResourceWorkflowView.swift",
]


ENGLISH_LITERAL_PURPOSE = (
    "Replace only app-owned English literal UI or accessibility copy in this frozen-B text-bearing surface with typed semantic keys; "
    "preserve V23 behavior and any Phase10-owned visual styling, token values, navigation, and feature flow."
)


# Concrete existing writers are deliberately added to the owning card instead
# of being shadowed by V30-only contracts.  Each is a finite, frozen-B path and
# is validated as a blob below.  New V30 files remain additive support, not the
# sole implementation mechanism.
EXISTING_SEAMS_BY_CARD: dict[str, list[tuple[str, str]]] = {
    "V30-P01-C04": [
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Version-forward the existing typed locale/catalog contract for the six independent globalization axes."),
        ("FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift", "Define device-local versus workspace-canonical globalization preference disposition in the existing settings contract."),
        ("FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift", "Persist only the allowed device-local globalization preference state through the existing adapter."),
        ("FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift", "Add report language/formatting/provenance axes to the existing document contract."),
        ("FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift", "Preserve language-independent canonical report projection identity while adding display metadata."),
        ("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift", "Bind backup identity/disposition to language-neutral canonical data."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Extend existing localization contract regression coverage."),
    ],
    "V30-P01-C05": [
        ("FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift", "Prove language/formatting changes cannot change canonical settings identity."),
        ("FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift", "Preserve language-neutral journal event identity and raw values."),
        ("FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift", "Enforce canonical mutation-journal identity across locale changes."),
        ("FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift", "Preserve replication journal bytes and replay identity across locale changes."),
        ("FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift", "Keep canonical writer receipt/identity invariant under display locale changes."),
        ("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift", "Keep backup identity language-neutral and historically stable."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift", "Keep canonical backup encoding independent of UI language and formatting locale."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift", "Keep canonical backup decoding independent of current UI language."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "Validate canonical backup identity without translated-data assumptions."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "Restore canonical identity without rewriting language-neutral data."),
        ("FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift", "Regression-test journal/checkpoint identity invariance."),
        ("FieldEvidenceAppTests/S6_3BackupValidationTests.swift", "Regression-test backup validation identity invariance."),
        ("FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift", "Regression-test atomic restore identity invariance."),
    ],
    "V30-P01-C06": [
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Expand the existing shipping locale/fallback contract beyond its en-only baseline."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Replace the existing runtimeLanguage=en resolution seam with Apple system/per-app effective-language resolution."),
        ("FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift", "Persist only privacy-preserving device-local fallback diagnostics through the existing adapter."),
        ("FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift", "Expose the existing typed settings capability port for safe system-Settings handoff."),
        ("FieldEvidenceApp/Features/Shell/AppShellView.swift", "Wire only the V30 Language & Region Settings entry point; preserve Phase10-owned shell navigation and brand."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Extend effective-language, fallback, and raw-key regression coverage."),
    ],
    "V30-P01-C07": [
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Route existing typed display formatting through the locale-aware contract without changing canonical values."),
        ("FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift", "Bind document language, formatting locale, paper, and provenance to existing report contracts."),
        ("FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift", "Use locale-aware display formatting in existing PDF/report rendering while preserving canonical snapshots."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift", "Preserve canonical timestamps while selecting explicit human-readable report formatting."),
        ("FieldEvidenceApp/Features/Issues/RecordWorkView.swift", "Replace only locale-sensitive date/number input and display formatting in the existing record-work UI."),
        ("FieldEvidenceApp/Features/Issues/WorkCoordinator.swift", "Replace only locale-sensitive date/number display formatting in the existing work coordinator."),
        ("FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift", "Regression-test locale-formatted report recovery without canonical drift."),
        ("FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift", "Regression-test explicit report formatting and delivery behavior."),
    ],
    "V30-P01-C08": [
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Make the existing catalog release/compatibility validation authoritative for versioned V30 releases."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Bind existing bundled catalog loading to offline release/provenance/rollback validation."),
        ("FieldEvidenceApp/Resources/Localizable.xcstrings", "Bind the existing source catalog to release digest and historical lookup metadata."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Extend existing release/locale validation regression coverage."),
    ],
    "V30-P02-C01": [
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Route normalized semantic English keys through the current typed catalog seam."),
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Enforce semantic-key/comment/placeholder/literal-disposition policy in the existing contract."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Extend existing localization/accessibility key coverage."),
        *[(path, ENGLISH_LITERAL_PURPOSE) for path in UI_LITERAL_OWNER_PATHS],
    ],
    "V30-P02-C02": [
        ("FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift", "Preserve Unicode at the canonical writer boundary."),
        ("FieldEvidenceApp/Domain/Replication/ChangeJournalContractsV1.swift", "Preserve Unicode in journal contract payloads and canonical identity."),
        ("FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift", "Preserve Unicode through mutation journal persistence and recovery."),
        ("FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift", "Preserve Unicode through local replication journal records."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift", "Preserve Unicode in canonical backup encoding."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift", "Preserve Unicode in canonical backup decoding."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "Validate Unicode-preserving backup package boundaries."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "Preserve Unicode through restore and recovery."),
        ("FieldEvidenceApp/Infrastructure/Media/EvidenceBundleStore.swift", "Preserve Unicode filenames/captions through evidence bundle storage."),
        ("FieldEvidenceApp/Infrastructure/ImportExport/ImportBulkLifecycleAdapterV1.swift", "Preserve Unicode through bulk import lifecycle boundaries."),
        ("FieldEvidenceApp/Infrastructure/ImportExport/EntityIdentityResolutionLifecycleAdapterV1.swift", "Preserve Unicode through entity identity import/recovery boundaries."),
        ("FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift", "Regression-test journal Unicode survival."),
        ("FieldEvidenceAppTests/S6_3BackupValidationTests.swift", "Regression-test backup Unicode survival."),
        ("FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift", "Regression-test restore Unicode survival."),
        ("FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift", "Regression-test import Unicode survival."),
    ],
    "V30-P02-C03": [
        ("FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift", "Extend existing semantic accessibility contracts for RTL/bidi focus/order safety."),
        ("FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift", "Remove ASCII-only/bidi-unsafe deterministic PDF behavior and preserve canonical report identity."),
        ("FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", "Preserve bidi-safe JSON display variants without changing machine keys."),
        ("FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift", "Apply bidi-safe document layout/rendering through the existing renderer."),
        ("FieldEvidenceApp/DesignSystem/WorklightComponents.swift", "Apply only semantic RTL direction, focus, and touch ordering; preserve Phase10 visual tokens and brand composition."),
        ("FieldEvidenceApp/Features/Shell/AppShellView.swift", "Apply only semantic tab/navigation ordering for RTL; preserve Phase10 shell visual composition."),
    ],
    "V30-P02-C04": [
        ("FieldEvidenceApp/Domain/Accessibility/SemanticAccessibilityContractsV1.swift", "Extend existing accessibility contract for Dynamic Type, localized labels, focus, and reachability."),
        ("FieldEvidenceApp/DesignSystem/WorklightComponents.swift", "Apply only Dynamic Type, long-text, touch-target, and accessibility reachability behavior; preserve Phase10 visual tokens and branding."),
        ("FieldEvidenceApp/Features/Shell/AppShellView.swift", "Apply only Dynamic Type/long-text navigation reachability; preserve Phase10 shell visual composition."),
        ("FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift", "Apply only Dynamic Type/long-text and accessibility reachability to the backup recovery surface."),
        ("FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift", "Apply only Dynamic Type/long-text and accessibility reachability to the backup validation surface."),
        ("FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift", "Apply only Dynamic Type/long-text and accessibility reachability to capture controls."),
        ("FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift", "Apply only Dynamic Type/long-text and accessibility reachability to outcome controls."),
        ("FieldEvidenceApp/Features/CheckRunner/PreflightView.swift", "Apply only Dynamic Type/long-text and accessibility reachability to preflight controls."),
        ("FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift", "Apply only Dynamic Type/long-text and accessibility reachability to receipt controls."),
        ("FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift", "Apply Dynamic Type/long-text recovery accessibility behavior."),
        ("FieldEvidenceApp/Features/Rounds/RoundSessionView.swift", "Apply Dynamic Type/long-text round-session accessibility behavior."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Extend localization/accessibility Dynamic Type regression coverage."),
        ("FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift", "Extend established accessibility golden coverage."),
    ],
    "V30-P02-C05": [
        ("FieldEvidenceApp/Domain/Search/SearchContractsV1.swift", "Version-forward existing search contracts for derived locale normalization and stable ties."),
        ("FieldEvidenceApp/Domain/Search/SearchPersistenceModelsV1.swift", "Version-forward existing persisted derived-search models without changing canonical identifiers."),
        ("FieldEvidenceApp/Application/Search/SearchCoordinatorV1.swift", "Route existing search coordination through versioned locale normalization."),
        ("FieldEvidenceApp/Infrastructure/Search/LocalSearchIndexStoreV1.swift", "Persist locale-normalized derived search rows only."),
        ("FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift", "Rebuild locale-normalized derived search safely from canonical records."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "Restore/rebuild only derived search normalization state."),
        ("FieldEvidenceApp/Infrastructure/Deletion/EraseAllService.swift", "Erase derived locale search state without affecting canonical data."),
        ("FieldEvidenceAppTests/V9_19LocalSearchTests.swift", "Extend existing local-search normalization/rebuild coverage."),
        ("FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift", "Extend restore/rebuild coverage for derived search state."),
    ],
    "V30-P02-C06": [
        ("FieldEvidenceApp/App/FieldEvidenceAppApp.swift", "Install only test-only pseudo/RTL/long-text launch injection; preserve Phase10 startup/brand behavior."),
        ("FieldEvidenceApp/Features/Shell/AppShellView.swift", "Consume only test-only pseudo/RTL/long-text harness state; preserve Phase10 shell behavior."),
        ("FieldEvidenceAppUITests/V23_P03_C16LocalizationAccessibilityUITests.swift", "Extend existing localization UI evidence with provisional pseudo cases."),
        ("FieldEvidenceAppUITests/V23_P04_C16ShellAccessibilityLocalizationUITests.swift", "Extend existing shell accessibility localization evidence with provisional pseudo cases."),
    ],
    "V30-P02-C07": [
        ("FieldEvidenceApp/Domain/Settings/SettingsContractsV1.swift", "Add typed language/region/report-language preference semantics to existing settings contracts."),
        ("FieldEvidenceApp/Infrastructure/Settings/PreferencesAdapterV1.swift", "Persist allowed device-local language/report preferences through the existing adapter."),
        ("FieldEvidenceApp/Application/Ports/SettingsCapabilityPortsV1.swift", "Expose typed language/region settings capability through the established port."),
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Bind Settings effective language to existing catalog/fallback contracts."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Resolve effective language and localized settings labels through the existing catalog."),
        ("FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift", "Add independent report-language selection to existing document contracts."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift", "Select explicit report language/formatting at the existing render seam."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift", "Preserve explicit report language through existing delivery behavior."),
        ("FieldEvidenceApp/Features/Shell/AppShellView.swift", "Wire only the Globalization Settings route; preserve Phase10 shell navigation/brand composition."),
    ],
    "V30-P03-C01": [
        ("FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift", "Distinguish authored/source/derived/report-chrome language in existing document contracts."),
        ("FieldEvidenceApp/Domain/Workflow/ReportSnapshotV1.swift", "Preserve source evidence and historical report snapshot identity across derived translations."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift", "Register language provenance without creating a parallel report projection path."),
        ("FieldEvidenceApp/Infrastructure/Persistence/WorkspaceWriterAdapterV1.swift", "Invalidate derived translations after canonical edit/redaction through the actual writer boundary."),
    ],
    "V30-P03-C02": [
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Localize current pending/saved/syncing/failed/recovery state copy through the existing catalog."),
        ("FieldEvidenceApp/Infrastructure/Persistence/StartupRouter.swift", "Preserve localized offline startup/recovery state truth through existing startup routing."),
        ("FieldEvidenceApp/Infrastructure/Persistence/StoreSessionCoordinator.swift", "Preserve localized sync/session state truth through the existing coordinator."),
        ("FieldEvidenceApp/Infrastructure/Replication/LocalChangeJournal/LocalChangeJournalV1.swift", "Preserve Unicode sync-state evidence without a new sync engine."),
        ("FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift", "Render existing recovery/sync-state truth with typed localized messages only."),
    ],
    "V30-P03-C03": [
        ("FieldEvidenceApp/Features/CheckRunner/CheckRunnerContracts.swift", "Version-forward existing required/optional/error semantics without changing canonical rules."),
        ("FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift", "Preserve canonical conditional form rules while allowing localized presentation."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Resolve field labels/instructions/errors through existing typed catalog keys."),
        ("FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift", "Localize existing field labels/required/error presentation without changing capture semantics."),
        ("FieldEvidenceApp/Features/CheckRunner/PreflightView.swift", "Localize existing required/preflight presentation without changing workflow semantics."),
    ],
    "V30-P03-C04": [
        ("FieldEvidenceApp/Domain/Reporting/AccessibleDocumentContractsV1.swift", "Version-forward existing accessible-document contracts for Unicode/font/paper/provenance."),
        ("FieldEvidenceApp/Infrastructure/Reporting/WorklightPDFRendererV1.swift", "Implement Unicode shaping/font embedding and Letter/A4 behavior in the actual PDF renderer."),
        ("FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift", "Remove existing ASCII question-mark substitution in the deterministic PDF path."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportRenderService.swift", "Use globalized renderer through the existing report render seam."),
        ("FieldEvidenceApp/Infrastructure/Reporting/AccessibleDocumentLifecycleAdapterV1.swift", "Preserve existing document lifecycle/provenance on globalized output."),
        ("FieldEvidenceAppTests/V9_38AccessibleDocumentTests.swift", "Extend accessible document renderer regression coverage."),
    ],
    "V30-P03-C05": [
        ("FieldEvidenceApp/Domain/ImportExport/ImportBulkContractsV1.swift", "Preserve language-neutral machine keys and add explicit localized-human variants in existing import/export contracts."),
        ("FieldEvidenceApp/Infrastructure/ImportExport/ImportBulkLifecycleAdapterV1.swift", "Apply locale manifests/formula safety/media references through the existing import/export lifecycle seam."),
        ("FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift", "Preserve stable JSON machine fields and add bounded human display metadata."),
        ("FieldEvidenceApp/Infrastructure/Diagnostics/DiagnosticExportV1.swift", "Keep diagnostic/export machine data stable across language changes."),
        ("FieldEvidenceAppTests/V9_72ImportBulkEngineTests.swift", "Extend existing import/export round-trip regression coverage."),
    ],
    "V30-P03-C06": [
        ("FieldEvidenceApp/Application/Reporting/ShopReportProfileCoordinatorV1.swift", "Select localized share/email/print chrome without changing report content identity."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportDeliveryCoordinator.swift", "Deliver explicit document language and localized subject/body templates through existing delivery code."),
        ("FieldEvidenceApp/Features/Reporting/ShopProfileOpenEvidenceHandoffView.swift", "Localize existing open-evidence handoff/share presentation."),
        ("FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift", "Localize app-owned mail chrome while preserving authored content."),
        ("FieldEvidenceApp/Features/Settings/FeedbackView.swift", "Localize feedback/share action chrome without changing Phase10 settings styling."),
    ],
    "V30-P03-C07": [
        ("FieldEvidenceApp/Application/Assistance/OCRProposalCoordinatorV1.swift", "Expose per-locale OCR truth through the existing assistance capability seam."),
        ("FieldEvidenceApp/Domain/VoiceStructuring/VoiceStructuringContractsV1.swift", "Represent exact OS/device/build speech/dictation capability without implying support."),
        ("FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift", "Render truthful assisted-input capability state in the existing voice surface."),
    ],
    "V30-P03-C08": [
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift", "Include catalog/font/renderer provenance only without changing canonical source content."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift", "Restore catalog/font/renderer provenance independently of current app language."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift", "Export historical catalog replay references through the existing backup path."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift", "Import historical catalog replay references through the existing backup path."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupRestoreService.swift", "Restore catalog replay and explicit missing-resource limitations."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "Validate catalog replay references and missing-resource limits."),
        ("FieldEvidenceApp/Infrastructure/Backup/StreamingArchiveService.swift", "Carry catalog/font/renderer references through streaming archive boundaries."),
        ("FieldEvidenceApp/Infrastructure/Search/SearchIndexRebuildCoordinatorV1.swift", "Rebuild derived search state after historical catalog restore."),
        ("FieldEvidenceAppTests/S6_2BackupExportTests.swift", "Extend backup export evidence for catalog replay."),
        ("FieldEvidenceAppTests/S6_3BackupValidationTests.swift", "Extend backup validation evidence for catalog replay."),
        ("FieldEvidenceAppTests/S6_4AtomicRestoreTests.swift", "Extend restore evidence for historical catalog replay."),
    ],
    "V30-P03-C09": [
        ("FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift", "Localize contextual restore/recovery messages and accessible actions only."),
        ("FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift", "Localize validation/recovery state and accessible actions only."),
        ("FieldEvidenceApp/Features/Reports/ReportFailureView.swift", "Localize report failure/recovery copy and accessible actions only."),
        ("FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift", "Localize onboarding/startup/recovery copy and accessible actions only."),
        ("FieldEvidenceApp/Features/Settings/EraseAllView.swift", "Localize destructive-action copy and accessible confirmations only."),
        ("FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift", "Localize recovery/support copy through the existing recovery surface."),
        ("FieldEvidenceApp/Infrastructure/Feedback/MailComposerAdapter.swift", "Localize support mail chrome while preserving user-authored content."),
    ],
}


for card_spec in CARD_SPECS:
    for seam_path, seam_purpose in EXISTING_SEAMS_BY_CARD.get(card_spec["cardID"], []):
        card_spec["paths"].append(e(seam_path, seam_purpose))


# The second audit pass adds durable producers/consumers that make the P03
# deltas real integrations.  It is kept separate so every addition remains
# reviewable against the named card rather than disappearing into a broad glob.
ADDITIONAL_EXISTING_SEAMS_BY_CARD: dict[str, list[tuple[str, str]]] = {
    "V30-P03-C01": [
        ("FieldEvidenceApp/Domain/Content/ContentProvenanceContractsV1.swift", "Preserve authored/source/derived content provenance through the established content contract."),
        ("FieldEvidenceApp/Domain/Packs/SurveyDefinitionContractsV1.swift", "Bind template/instruction language to the existing survey definition contract."),
        ("FieldEvidenceApp/Infrastructure/Content/ContentContractRegistryV1.swift", "Register content-language provenance through the existing content registry."),
        ("FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift", "Preserve language provenance and no-translation-service boundary in packaged content execution."),
        ("FieldEvidenceApp/Infrastructure/Finalization/ReportSnapshotEncoderV1.swift", "Preserve source/derived content provenance in final report snapshot encoding."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift", "Preserve authored source and derived-translation invalidation provenance in canonical backup output."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift", "Restore authored source and derived-translation provenance without using current app language."),
        ("FieldEvidenceAppTests/V9_15ContentReferenceProvenanceTests.swift", "Regression-test source/content provenance invariants."),
        ("FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift", "Regression-test template/instruction language semantics."),
        ("FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift", "Regression-test report snapshot provenance."),
    ],
    "V30-P03-C02": [
        ("FieldEvidenceApp/Domain/Replication/SyncClassificationRegistryV1.swift", "Localize only existing sync classifications without creating a new sync engine."),
        ("FieldEvidenceApp/Infrastructure/Persistence/CurrentSyncClassificationCatalogV1.swift", "Use the current typed sync-classification catalog as the localization source."),
        ("FieldEvidenceApp/Infrastructure/Replication/IntegrationEventProjectionV1.swift", "Preserve localized sync event truth at the existing projection boundary."),
        ("FieldEvidenceApp/Infrastructure/Persistence/MutationJournal/MutationJournalStoreV1.swift", "Preserve sync-state evidence/recovery identity through the mutation journal."),
        ("FieldEvidenceApp/Features/Recovery/RecoveryCenterView.swift", "Render localized offline/recovery state through the existing recovery surface."),
        ("FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift", "Render only existing offline startup/recovery state with typed localized text; preserve Phase10 visual styling."),
        ("FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift", "Regression-test localized sync state without journal drift."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Regression-test sync-state localization/accessibility."),
    ],
    "V30-P03-C03": [
        ("FieldEvidenceApp/Domain/InspectionKernel/ResponseFieldDefinitionV1.swift", "Preserve canonical response field definition semantics while adding localized presentation."),
        ("FieldEvidenceApp/Domain/InspectionKernel/ResponseValueV1.swift", "Preserve canonical response values across localized labels/units/numerals."),
        ("FieldEvidenceApp/Domain/InspectionKernel/WorkflowGrammarContractsV1.swift", "Preserve canonical grammar/condition semantics under localized presentation."),
        ("FieldEvidenceApp/Domain/InspectionKernel/WorkflowGraphValidatorV1.swift", "Validate localized presentation cannot change canonical workflow graph rules."),
        ("FieldEvidenceApp/Application/Packs/SurveyDefinitionCoordinatorV1.swift", "Coordinate existing survey definitions with localized presentation."),
        ("FieldEvidenceApp/Application/Workflow/GuidedSurveyFlowCoordinatorV1.swift", "Coordinate required/error/conditional display through existing guided-survey flow."),
        ("FieldEvidenceApp/Infrastructure/Packs/SurveyDefinitionLifecycleAdapterV1.swift", "Preserve lifecycle/snapshot behavior while adding localizable form presentation."),
        ("FieldEvidenceApp/Infrastructure/Packs/PackageSandboxRunnerV1.swift", "Preserve packaged form rule execution while localizing labels/instructions."),
        ("FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift", "Localize existing outcome/error presentation only; preserve Phase10 visual styling and workflow semantics."),
        ("FieldEvidenceAppTests/V9_39SurveyDefinitionTests.swift", "Regression-test localized survey definition semantics."),
        ("FieldEvidenceAppTests/V9_83GuidedSurveyFlowTests.swift", "Regression-test guided-survey required/error/condition semantics."),
        ("FieldEvidenceAppTests/V9_13TypedResponseTests.swift", "Regression-test typed response values across locale presentation."),
    ],
    "V30-P03-C04": [
        ("FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift", "Preserve canonical projection identity while adding Unicode/display provenance."),
        ("FieldEvidenceApp/Application/Reporting/AccessibleDocumentCoordinatorV1.swift", "Route globalized documents through the existing accessible-document coordinator."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift", "Preserve historical deterministic replay and provenance through the existing history seam."),
        ("FieldEvidenceApp/Infrastructure/Reporting/SnapshotValidatorV1.swift", "Validate Unicode/globalized render inputs before output generation."),
        ("FieldEvidenceAppTests/S4_1DeterministicRendererTests.swift", "Regression-test deterministic renderer identity after Unicode support."),
        ("FieldEvidenceAppTests/S4_2PDFRecoveryTests.swift", "Regression-test Unicode PDF recovery."),
    ],
    "V30-P03-C05": [
        ("FieldEvidenceApp/Application/ImportExport/ImportBulkCoordinatorV1.swift", "Route stable machine/localized-human import-export semantics through the existing coordinator."),
        ("FieldEvidenceApp/Infrastructure/ImportExport/EntityIdentityResolutionLifecycleAdapterV1.swift", "Preserve stable identity during localized import/export normalization."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalEncoderV1.swift", "Keep machine export/backup canonical encoding language-neutral."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupCanonicalDecoderV1.swift", "Keep machine import/backup canonical decoding language-neutral."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupExportService.swift", "Export locale manifests without changing canonical backup fields."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupImportService.swift", "Import locale manifests without changing canonical backup fields."),
        ("FieldEvidenceApp/Infrastructure/Backup/BackupPackageValidatorV1.swift", "Validate locale manifests/formula safety without changing canonical machine fields."),
        ("FieldEvidenceAppTests/V9_95PartyContactSiteRoleImportTests.swift", "Regression-test stable imported identifiers under localized-human variants."),
        ("FieldEvidenceAppTests/S6_2BackupExportTests.swift", "Regression-test machine export/backup locale manifest boundaries."),
    ],
    "V30-P03-C06": [
        ("FieldEvidenceApp/Domain/Labels/AssetLabelContractsV1.swift", "Add explicit document-language/chrome semantics through the existing asset-label contract."),
        ("FieldEvidenceApp/Application/Labels/AssetLabelCoordinatorV1.swift", "Route localized label generation through the existing label coordinator."),
        ("FieldEvidenceApp/Infrastructure/Reporting/AssetLabelLifecycleAdapterV1.swift", "Preserve label lifecycle/provenance with localized app-owned chrome."),
        ("FieldEvidenceApp/App/Composition/ProductionCompositionRoot.swift", "Compose existing delivery/mail/label localization seams without a parallel sending flow."),
        ("FieldEvidenceApp/Features/Reports/ReportDetailView.swift", "Localize only existing report share/print chrome in the detail surface; preserve Phase10 styling."),
        ("FieldEvidenceApp/Features/Reports/ReportsRootView.swift", "Localize only existing report share/print chrome in the root surface; preserve Phase10 styling."),
        ("FieldEvidenceAppTests/S4_3ReportDeliveryTests.swift", "Regression-test report delivery with explicit document language."),
        ("FieldEvidenceAppTests/V9_93AssetLabelOutputTests.swift", "Regression-test localized label output and provenance."),
        ("FieldEvidenceAppTests/V9_52AssetLabelTests.swift", "Regression-test asset-label lifecycle semantics."),
    ],
    "V30-P03-C07": [
        ("FieldEvidenceApp/Domain/Assistance/OCRProposalContractsV1.swift", "Expose locale capability truth through the existing OCR proposal contract."),
        ("FieldEvidenceApp/Infrastructure/Assistance/OCRProposalLifecycleAdapterV1.swift", "Route truthful OCR capability through the existing lifecycle adapter."),
        ("FieldEvidenceApp/Domain/Assistance/DictationLocationProposalContractsV1.swift", "Expose locale capability truth through existing dictation proposal contracts."),
        ("FieldEvidenceApp/Application/Assistance/DictationLocationProposalCoordinatorV1.swift", "Coordinate truthful dictation capability through the existing coordinator."),
        ("FieldEvidenceApp/Infrastructure/Assistance/DictationLocationProposalLifecycleAdapterV1.swift", "Route truthful dictation lifecycle state without implying unsupported recognition."),
        ("FieldEvidenceApp/Domain/VoiceCapture/StructuredVoiceCaptureContractsV1.swift", "Represent exact structured voice capture capability truth."),
        ("FieldEvidenceApp/Application/VoiceCapture/VoicePushToTalkCoordinatorV1.swift", "Coordinate exact voice capability truth through the existing capture flow."),
        ("FieldEvidenceApp/Infrastructure/VoiceCapture/OnDevicePushToTalkVoiceCaptureAdapterV1.swift", "Read OS/device capability truth from the existing on-device adapter."),
        ("FieldEvidenceApp/Application/VoiceStructuring/VoiceStructuringServiceV1.swift", "Preserve truthful voice structuring capability semantics."),
        ("FieldEvidenceApp/Infrastructure/System/SystemCapabilityAdaptersV1.swift", "Bind exact OS/device/build capability evidence through the existing system adapter."),
        ("FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift", "Represent unavailable locale capability without translated-label overclaim."),
        ("FieldEvidenceAppTests/V9_86OCRProposalTests.swift", "Regression-test OCR capability truth."),
        ("FieldEvidenceAppTests/V9_87DictationLocationProposalTests.swift", "Regression-test dictation capability truth."),
        ("FieldEvidenceAppTests/V9_108StructuredVoiceCaptureTests.swift", "Regression-test voice capture capability truth."),
        ("FieldEvidenceAppTests/V9_64StructuredVoiceProposalTests.swift", "Regression-test structured voice proposal truth."),
    ],
    "V30-P03-C08": [
        ("FieldEvidenceApp/Domain/Backup/V4BackupContracts.swift", "Bind historical catalog replay to the canonical V4 backup contract."),
        ("FieldEvidenceApp/Domain/Backup/V4BackupImportContracts.swift", "Bind historical catalog replay to the canonical V4 backup import contract."),
        ("FieldEvidenceApp/Domain/Backup/RestoreIdentityV1.swift", "Preserve restore identity independent of current language/catalog."),
        ("FieldEvidenceApp/Infrastructure/Backup/KernelBackupRestoreRegistryV4.swift", "Register catalog replay through the existing kernel restore registry."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Restore historical catalog references through the existing bundled catalog seam."),
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Validate historical catalog compatibility and explicit missing-resource limitations."),
        ("FieldEvidenceApp/Infrastructure/Reporting/ReportHistoryCoordinator.swift", "Preserve historical report replay against catalog/font/renderer references."),
        ("FieldEvidenceAppTests/V9_05RestoreIdentityTests.swift", "Regression-test restore identity independent of current language."),
        ("FieldEvidenceAppTests/V9_ChangeJournalCheckpointReplayTests.swift", "Regression-test checkpoint/replay behavior after catalog restore."),
    ],
    "V30-P03-C09": [
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Close critical surface catalog/key coverage through the existing localization contract."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Resolve critical recovery/help/permission/support copy through the existing catalog."),
        ("FieldEvidenceApp/Infrastructure/Diagnostics/SystemHealthContractsV1.swift", "Preserve truthful system-health/error state semantics under localized display."),
        ("FieldEvidenceApp/Features/VoiceCapture/VoicePushToTalkCaptureView.swift", "Localize assisted-input permission/recovery copy through the existing non-S10 voice surface."),
        ("FieldEvidenceApp/Info.plist", "Keep declared permission identity stable while aligning the complete permission localization inventory."),
        ("FieldEvidenceApp/InfoPlist.xcstrings", "Complete camera/microphone/speech permission string localization through the existing InfoPlist catalog."),
        ("FieldEvidenceApp/Domain/Capability/CapabilityAvailabilityContractsV1.swift", "Keep permission/capability truth independent of translated labels."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Correct and extend permission/localization regression assertions."),
        ("FieldEvidenceAppTests/S8_2GoldenAccessibilityTests.swift", "Regression-test localized accessibility on critical surfaces."),
        ("FieldEvidenceAppTests/S8_3DiagnosticPrivacyTests.swift", "Regression-test localized diagnostic/privacy critical states."),
        ("FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift", "Localize only permission/Open Settings critical copy and accessibility actions; preserve Phase10 styling."),
        ("FieldEvidenceApp/Features/Settings/BackupExportView.swift", "Localize only backup export critical copy and accessibility actions; preserve Phase10 styling."),
        ("FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift", "Localize only diagnostic export critical copy and accessibility actions; preserve Phase10 styling."),
        ("FieldEvidenceApp/Features/Settings/FeedbackView.swift", "Localize only support/feedback critical copy and accessibility actions; preserve Phase10 styling."),
        ("FieldEvidenceApp/Features/Reports/ReportDetailView.swift", "Localize only report detail critical recovery/share copy and accessibility actions; preserve Phase10 styling."),
        ("FieldEvidenceApp/Features/Reports/ReportsRootView.swift", "Localize only reports root critical recovery/share copy and accessibility actions; preserve Phase10 styling."),
    ],
    "V30-P04-C07": [
        ("FieldEvidenceApp/Resources/Localizable.xcstrings", "Integrate all six complete locale variants into the canonical iOS string catalog."),
        ("FieldEvidenceApp/InfoPlist.xcstrings", "Integrate complete locale variants for permission string catalog entries."),
        ("FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift", "Validate six-locale catalog completeness/release compatibility through the canonical contract."),
        ("FieldEvidenceApp/Infrastructure/Localization/BundledLocalizationCatalogV1.swift", "Wire six locale resources into the existing bundled localization runtime seam."),
        ("FieldEvidenceAppTests/V9_22LocalizationAccessibilityTests.swift", "Prove six-locale catalog completeness through the established test owner."),
    ],
}


for card_spec in CARD_SPECS:
    for seam_path, seam_purpose in ADDITIONAL_EXISTING_SEAMS_BY_CARD.get(card_spec["cardID"], []):
        if any(existing_path == seam_path for _, existing_path, _ in card_spec["paths"]):
            raise RuntimeError(f"duplicate audited seam in {card_spec['cardID']}: {seam_path}")
        card_spec["paths"].append(e(seam_path, seam_purpose))


# Every listed R2 authorization is an exact path/card policy, not an inferred
# wildcard.  The builder below refuses both an unlisted reserved overlap and a
# stale listing that fails to appear in its card fence.
PREAUTHORIZED_S10_OVERLAPS: dict[str, dict[str, dict[str, str]]] = {}


def authorize_s10_overlap(card_id: str, path: str, purpose: str, writer_lane: str) -> None:
    PREAUTHORIZED_S10_OVERLAPS.setdefault(card_id, {})[path] = {
        "boundedPurpose": purpose,
        "reconciliationObligation": "REPLAY_OR_REIMPLEMENT_AFTER_S_NO_PRE_S10_CREDIT",
        "writerLane": writer_lane,
    }


authorize_s10_overlap(
    "V30-P00-C05",
    ".github/workflows/ios-ci.yml",
    "change only the phase/v30-globalization branch copy of the existing iOS CI controller to consume docs/design/v30/execution/V30_CI_SELECTION.json typed selector; preserve pinned runner/toolchain/simulator/watchdogs/evidence/commands, route/ref isolation, and no main or Phase10 mutation",
    "V30-P00-C05-PROVISIONAL-CI-CONTROLLER",
)
authorize_s10_overlap(
    "V30-P00-C05",
    "Scripts/ui-smoke.sh",
    "change only the phase/v30-globalization branch copy to consume docs/design/v30/execution/V30_CI_SELECTION.json typed selector; preserve pinned UI commands, watchdogs, evidence, route/ref isolation, and no main or Phase10 mutation",
    "V30-P00-C05-PROVISIONAL-CI-CONTROLLER",
)


for path in UI_LITERAL_OWNER_PATHS[:25]:
    authorize_s10_overlap(
        "V30-P02-C01",
        path,
        f"replace only app-owned English literal/accessibility copy in {path}; preserve Phase10 visual styling, token values, navigation, and feature flow",
        "V30-P02-C01-ENGLISH-NORMALIZER",
    )

for path in [
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
]:
    authorize_s10_overlap(
        "V30-P01-C06",
        path,
        f"wire only the V30 Language & Region Settings entry point in {path}; preserve Phase10 shell navigation and brand",
        "V30-P01-C06-SETTINGS-RESOLUTION-INTEGRATOR",
    )

for path in [
    "FieldEvidenceApp/Features/Issues/RecordWorkView.swift",
    "FieldEvidenceApp/Features/Issues/WorkCoordinator.swift",
]:
    authorize_s10_overlap(
        "V30-P01-C07",
        path,
        f"replace only locale-sensitive date/number input or display formatting in {path}; preserve Phase10 visual styling and workflow behavior",
        "V30-P01-C07-LOCALE-FORMAT-INTEGRATOR",
    )

for path in [
    "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
]:
    authorize_s10_overlap(
        "V30-P02-C03",
        path,
        f"apply only semantic RTL/bidi direction, focus, or touch ordering in {path}; preserve Phase10 visual tokens and brand composition",
        "V30-P02-C03-RTL-SEMANTICS-INTEGRATOR",
    )

for path in [
    "FieldEvidenceApp/DesignSystem/WorklightComponents.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
    "FieldEvidenceApp/Features/CheckRunner/ValueReceiptView.swift",
]:
    authorize_s10_overlap(
        "V30-P02-C04",
        path,
        f"apply only Dynamic Type, long-text, touch-target, and accessibility reachability in {path}; preserve Phase10 visual tokens and branding",
        "V30-P02-C04-ADAPTIVE-ACCESSIBILITY-INTEGRATOR",
    )

for path in [
    "FieldEvidenceApp/App/FieldEvidenceAppApp.swift",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
]:
    authorize_s10_overlap(
        "V30-P02-C06",
        path,
        f"install or consume only test-only pseudo/RTL/long-text launch harness state in {path}; preserve Phase10 startup, shell, and brand behavior",
        "V30-P02-C06-PSEUDO-HARNESS-INTEGRATOR",
    )

authorize_s10_overlap(
    "V30-P02-C07",
    "FieldEvidenceApp/Features/Shell/AppShellView.swift",
    "wire only the V30 Globalization Settings route; preserve Phase10 shell navigation and brand composition",
    "V30-P02-C07-SETTINGS-SURFACE-INTEGRATOR",
)
authorize_s10_overlap(
    "V30-P03-C02",
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "render only existing recovery/sync-state truth with typed localized messages; preserve Phase10 visual styling",
    "V30-P03-C02-SYNC-STATE-INTEGRATOR",
)
authorize_s10_overlap(
    "V30-P03-C02",
    "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
    "render only existing offline startup/recovery state with typed localized text; preserve Phase10 visual styling and shell behavior",
    "V30-P03-C02-SYNC-STATE-INTEGRATOR",
)
for path in [
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/CheckRunner/PreflightView.swift",
    "FieldEvidenceApp/Features/CheckRunner/OutcomeReviewView.swift",
]:
    authorize_s10_overlap(
        "V30-P03-C03",
        path,
        f"localize only existing field label/required/error presentation in {path}; preserve Phase10 visual styling and canonical workflow semantics",
        "V30-P03-C03-FORM-SEMANTICS-INTEGRATOR",
    )
authorize_s10_overlap(
    "V30-P03-C06",
    "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "localize only feedback/share action chrome in FeedbackView; preserve Phase10 settings styling and user-authored content",
    "V30-P03-C06-SHARE-SURFACE-INTEGRATOR",
)
for path in [
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
]:
    authorize_s10_overlap(
        "V30-P03-C06",
        path,
        f"localize only existing report share/print chrome in {path}; preserve Phase10 styling and report content identity",
        "V30-P03-C06-SHARE-SURFACE-INTEGRATOR",
    )
for path in [
    "FieldEvidenceApp/Features/Backup/BackupRestoreProgressView.swift",
    "FieldEvidenceApp/Features/Backup/BackupValidationSummaryView.swift",
    "FieldEvidenceApp/Features/Reports/ReportFailureView.swift",
    "FieldEvidenceApp/Features/Shell/StartupMaintenanceView.swift",
    "FieldEvidenceApp/Features/Settings/EraseAllView.swift",
]:
    authorize_s10_overlap(
        "V30-P03-C09",
        path,
        f"localize only critical recovery/destructive/support copy and accessible actions in {path}; preserve Phase10 visual styling and workflow behavior",
        "V30-P03-C09-CRITICAL-SURFACE-INTEGRATOR",
    )
for path in [
    "FieldEvidenceApp/Features/CheckRunner/CaptureStepView.swift",
    "FieldEvidenceApp/Features/Settings/BackupExportView.swift",
    "FieldEvidenceApp/Features/Settings/DiagnosticExportView.swift",
    "FieldEvidenceApp/Features/Settings/FeedbackView.swift",
    "FieldEvidenceApp/Features/Reports/ReportDetailView.swift",
    "FieldEvidenceApp/Features/Reports/ReportsRootView.swift",
]:
    authorize_s10_overlap(
        "V30-P03-C09",
        path,
        f"localize only critical recovery/destructive/support/permission copy and accessibility actions in {path}; preserve Phase10 visual styling and workflow behavior",
        "V30-P03-C09-CRITICAL-SURFACE-INTEGRATOR",
    )
authorize_s10_overlap(
    "V30-P04-C07",
    "FieldEvidenceApp.xcodeproj/project.pbxproj",
    "add only V30 localization known-region/resource membership required for six locales; preserve Phase10-owned settings",
    "V30-P04-C07-SERIALIZED-INTEGRATOR",
)


# An existing seam may be touched by several cards only if each card is ordered
# through this named provisional writer lane.  The output includes only paths
# that actually have multiple owners, together with their exact ordinal order.
SERIALIZED_PRODUCT_PATH_RATIONALES: dict[str, str] = {}
for seam_map in (EXISTING_SEAMS_BY_CARD, ADDITIONAL_EXISTING_SEAMS_BY_CARD):
    for seam_entries in seam_map.values():
        for seam_path, _ in seam_entries:
            SERIALIZED_PRODUCT_PATH_RATIONALES.setdefault(
                seam_path,
                "Existing V23 integration seam; card-scoped mutations are serialized in card ordinal order and replayed/reimplemented after accepted S.",
            )


IMMUTABLE_BOOTSTRAP_AUTHORITY_PATHS = [
    "docs/design/v30/authority/V30PreS10ProvisionalImplementationAuthorityV1.json",
    "docs/design/v30/authority/V30PackageManifestV1.json",
    "docs/design/v30/EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v30/EXPANSION_V30_FOUNDATION_PLAN.md",
    "docs/design/v30/EXPANSION_V30_HANDOFF.md",
    "docs/design/v30/NEXT_CODEX_SESSION_PROMPT.md",
    "docs/design/v30/authority/V30CardRegisterV1.json",
    "docs/design/v30/authority/V30DirectDependencyGraphV1.json",
    "docs/design/v30/authority/V30LocaleRegistryV1.json",
    "docs/design/v30/authority/V30V24DispositionProjectionV1.json",
    "docs/design/v30/authority/V30PreS10PathFencesV1.json",
]


def path_from_spec(spec: tuple[str, str, str]) -> dict[str, Any]:
    kind, path, purpose = spec
    if kind == "NEW":
        return expected_absent(path, purpose)
    if kind == "EXISTING":
        return existing(path, purpose)
    raise RuntimeError(f"unknown path kind: {kind}")


def path_is_safe(path: str) -> bool:
    forbidden = ("*", "?", "[", "]", "{", "}", "\\", "//")
    return bool(path) and not path.startswith("/") and not path.endswith("/") and not any(token in path for token in forbidden)


def build_document() -> dict[str, Any]:
    actual_head = run_git("rev-parse", "HEAD")
    actual_tree = run_git("rev-parse", "HEAD^{tree}")
    if actual_head != BASE_HEAD or actual_tree != BASE_TREE:
        raise RuntimeError(
            "frozen V23 base mismatch: "
            f"expected {BASE_HEAD}/{BASE_TREE}, observed {actual_head}/{actual_tree}"
        )

    reservation_file = FROZEN_V23 / RESERVATION_RELATIVE_PATH
    reservation_raw = read_bytes(reservation_file)
    if sha256(reservation_raw) != RESERVATION_RAW_SHA256:
        raise RuntimeError("frozen S10 reservation raw SHA-256 mismatch")
    reservation = json.loads(reservation_raw.decode("utf-8"))
    reserved_paths = reservation.get("reservedPaths")
    if not isinstance(reserved_paths, list) or len(reserved_paths) != 86 or len(set(reserved_paths)) != 86:
        raise RuntimeError("frozen S10 reservation must contain exactly 86 unique paths")
    if reservation.get("contentDigest") != RESERVATION_CONTENT_DIGEST:
        raise RuntimeError("frozen S10 reservation content digest mismatch")

    cards: list[dict[str, Any]] = []
    shared_paths = set(SHARED_EXECUTION_PATHS)
    shared_writer_order = list(EXECUTABLE_CARD_IDS)
    all_allowed: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for spec in CARD_SPECS:
        status = spec.get("status", "PRE_S10_PROVISIONAL_ELIGIBLE")
        paths: list[dict[str, Any]] = []
        if status != "CONFLICT_HOLD":
            paths.extend(common_execution_paths())
            paths.extend(path_from_spec(item) for item in spec["paths"])
        if len({item["path"] for item in paths}) != len(paths):
            raise RuntimeError(f"duplicate path within {spec['cardID']}")
        for item in paths:
            if not path_is_safe(item["path"]):
                raise RuntimeError(f"unsafe non-expanded path: {item['path']}")
            all_allowed.setdefault(item["path"], []).append((spec["cardID"], item))
        s10_shared = [item["path"] for item in paths if item["path"] in reserved_paths]
        tuples: list[dict[str, Any]] = []
        policies = PREAUTHORIZED_S10_OVERLAPS.get(spec["cardID"], {})
        for item in paths:
            if item["path"] not in reserved_paths:
                continue
            policy = policies.get(item["path"])
            if policy is None:
                raise RuntimeError(
                    f"S10 overlap lacks an externally authorized exact tuple: {spec['cardID']} {item['path']}"
                )
            if item["classification"] != "EXISTING_BLOB":
                raise RuntimeError(f"S10 overlap must bind an existing frozen-B blob: {item['path']}")
            tuples.append(
                {
                    "boundedPurpose": policy["boundedPurpose"],
                    "cardID": spec["cardID"],
                    "expectedBBlobOID": item["expectedBBlobOID"],
                    "expectedBSHA256": item["expectedBSHA256"],
                    "path": item["path"],
                    "reconciliationObligation": policy["reconciliationObligation"],
                    "writerLane": policy["writerLane"],
                }
            )
        if set(policies) != set(s10_shared):
            raise RuntimeError(
                f"stale or incomplete preauthorized tuple set for {spec['cardID']}: "
                f"policies={sorted(policies)} overlaps={sorted(s10_shared)}"
            )
        card: dict[str, Any] = {
            "allowedPaths": paths,
            "cardID": spec["cardID"],
            "class": spec["class"],
            "directPrerequisites": spec["directPrerequisites"],
            "ordinal": spec["ordinal"],
            "preAuthorizedOverlapTuples": tuples,
            "s10SharedPaths": s10_shared,
            "status": status,
            "title": spec["title"],
        }
        if status == "CONFLICT_HOLD":
            hold_paths = []
            for hold in spec["conflictHoldPaths"]:
                hold = dict(hold)
                if hold["path"] not in reserved_paths:
                    raise RuntimeError(f"conflict-hold path is not S10-reserved: {hold['path']}")
                oid, digest = frozen_blob(hold["path"])
                hold["frozenBBlobOID"] = oid
                hold["frozenBSHA256"] = digest
                hold_paths.append(hold)
            card["conflictHoldPaths"] = hold_paths
            card["holdRule"] = "NO_MUTATION. Keep each conflicting path outside allowedPaths until a pre-existing exact external tuple is installed."
        cards.append(card)

    expected_ids = [spec["cardID"] for spec in CARD_SPECS]
    if len(cards) != 37 or [card["cardID"] for card in cards] != expected_ids:
        raise RuntimeError("card sequence must be the closed 37-card P00-P04 program")
    if EXECUTABLE_CARD_IDS != [card["cardID"] for card in cards]:
        raise RuntimeError("executable writer order is inconsistent with cards 1-37")

    serialized_product_records: list[dict[str, Any]] = []
    for path, owner_entries in all_allowed.items():
        owners = [owner for owner, _ in owner_entries]
        if path in shared_paths:
            if owners != shared_writer_order:
                raise RuntimeError(f"serialized shared path writer order mismatch for {path}: {owners}")
            continue
        if len(owners) <= 1:
            continue
        rationale = SERIALIZED_PRODUCT_PATH_RATIONALES.get(path)
        if rationale is None:
            raise RuntimeError(f"unserialized multi-card mutable path {path}: {owners}")
        for _, item in owner_entries:
            item["serializedSharedPath"] = True
        serialized_product_records.append(
            {
                "path": path,
                "rationale": rationale,
                "writerLane": "V30-PRE-S10-ORDINAL-SERIALIZED-EXISTING-SEAM",
                "writerOrder": owners,
            }
        )
    if any(path in all_allowed for path in IMMUTABLE_BOOTSTRAP_AUTHORITY_PATHS):
        raise RuntimeError("immutable bootstrap authority artifact appeared in a mutable fence")

    return {
        "authorityID": AUTHORITY_ID,
        "base": {
            "branch": BASE_BRANCH,
            "head": BASE_HEAD,
            "tree": BASE_TREE,
            "worktree": str(FROZEN_V23),
        },
        "cardCount": 37,
        "cards": cards,
        "fenceRules": {
            "forbiddenInheritedMutationPaths": [
                "docs/execution/CURRENT_TASK.md",
                "docs/execution/HANDOFF.md",
                "Scripts/ci-selection.json",
            ],
            "immutableBootstrapAuthorityRule": "Installed authority artifacts are read-only support inputs and are never card-mutable paths.",
            "phase10CheckoutRule": "C:\\AssetRounds is NO_READ_NO_WRITE_NO_POLL for every pre-S10 card.",
            "s10OverlapRule": "An S10-reserved path may be mutable only when this R2 artifact carries its exact card/path/frozen-B blob/bounded-purpose/writer/reconciliation tuple; every such mutation is provisional and must be replayed or reimplemented after accepted S.",
        },
        "immutableBootstrapAuthorityPaths": [
            {
                "classification": "EXPECTED_ABSENT_NEW_PATH_AT_B_READ_ONLY_AFTER_EXTERNAL_INSTALL",
                "path": path,
            }
            for path in IMMUTABLE_BOOTSTRAP_AUTHORITY_PATHS
        ],
        "schema": "V30PreS10PathFencesV1",
        "schemaVersion": 1,
        "frozenBTextBearingLiteralInventory": {
            "cardID": "V30-P02-C01",
            "detectionBasis": "Frozen-B SwiftUI literal surface inventory using concrete control/title/dialog/accessibility call sites; every listed path is explicitly fenced rather than matched by a wildcard.",
            "pathCount": len(UI_LITERAL_OWNER_PATHS),
            "paths": UI_LITERAL_OWNER_PATHS,
        },
        "serializedSharedPaths": [
            {
                "path": path,
                "rationale": rationale,
                "writerLane": "V30_PROVISIONAL_SINGLE_WRITER",
                "writerOrder": shared_writer_order,
            }
            for path, rationale in SHARED_EXECUTION_PATHS.items()
        ] + sorted(serialized_product_records, key=lambda item: item["path"]),
        "s10Reservation": {
            "contentDigest": RESERVATION_CONTENT_DIGEST,
            "rawSHA256": RESERVATION_RAW_SHA256,
            "reservedPathCount": 86,
            "sourcePath": RESERVATION_RELATIVE_PATH,
        },
        "summary": {
            "conflictHoldCardIDs": [],
            "executableCardCount": 37,
            "perCardPathCounts": [
                {
                    "cardID": card["cardID"],
                    "existingBlobCount": sum(
                        item["classification"] == "EXISTING_BLOB"
                        for item in card["allowedPaths"]
                    ),
                    "expectedAbsentNewPathCount": sum(
                        item["classification"] == "EXPECTED_ABSENT_NEW_PATH"
                        for item in card["allowedPaths"]
                    ),
                    "s10SharedPathCount": len(card["s10SharedPaths"]),
                }
                for card in cards
            ],
            "preAuthorizedOverlapTupleCount": sum(len(card["preAuthorizedOverlapTuples"]) for card in cards),
            "s10SharedPathCount": sum(len(card["s10SharedPaths"]) for card in cards),
            "serializedExistingProductPathCount": len(serialized_product_records),
            "uniqueAllowedPathCount": len(all_allowed),
        },
    }


def canonical_bytes(document: dict[str, Any]) -> bytes:
    return (json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")


def validate_output(document: dict[str, Any]) -> None:
    if document.get("schema") != "V30PreS10PathFencesV1":
        raise RuntimeError("schema mismatch")
    if document.get("authorityID") != AUTHORITY_ID:
        raise RuntimeError("authority ID mismatch")
    if document.get("cardCount") != 37 or len(document.get("cards", [])) != 37:
        raise RuntimeError("closed card count mismatch")
    for card in document["cards"]:
        allowed = card["allowedPaths"]
        if card["status"] == "CONFLICT_HOLD":
            if allowed or not card.get("conflictHoldPaths"):
                raise RuntimeError("CONFLICT_HOLD must have no mutable allowed paths and at least one held path")
        for item in allowed:
            if item["classification"] == "EXISTING_BLOB":
                oid, digest = frozen_blob(item["path"])
                if (oid, digest) != (item["expectedBBlobOID"], item["expectedBSHA256"]):
                    raise RuntimeError(f"frozen blob drift: {item['path']}")
            elif item["classification"] == "EXPECTED_ABSENT_NEW_PATH":
                assert_absent_at_b(item["path"])
            else:
                raise RuntimeError(f"unknown path classification: {item['classification']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apply", action="store_true", help="write the deterministic JSON artifact")
    group.add_argument("--check", action="store_true", help="verify the artifact exactly matches frozen authority")
    args = parser.parse_args()
    document = build_document()
    validate_output(document)
    payload = canonical_bytes(document)
    if args.apply:
        OUTPUT.write_bytes(payload)
        print(f"APPLIED {OUTPUT.name} sha256={sha256(payload)} bytes={len(payload)}")
        return 0
    if not OUTPUT.is_file():
        raise RuntimeError(f"missing generated artifact: {OUTPUT}")
    actual = read_bytes(OUTPUT)
    if actual != payload:
        raise RuntimeError(
            f"artifact drift: expected sha256={sha256(payload)} bytes={len(payload)} "
            f"observed sha256={sha256(actual)} bytes={len(actual)}"
        )
    print(f"CHECK PASS {OUTPUT.name} sha256={sha256(payload)} bytes={len(payload)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
