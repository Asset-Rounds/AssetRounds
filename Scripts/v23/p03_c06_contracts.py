#!/usr/bin/env python3
"""Deterministic, manifest-driven Card 37 contract projections."""
from __future__ import annotations

import base64
import copy
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

CARD = "V23-P03-C06"
APP_BASE_HEAD = "4dc8154790cc11748d26db9d3d70361e926ddb1e"
APP_BASE_TREE = "15b8fc7dc63c8f71bbfe1eb75d86611e2e483647"
COORDINATION_HEAD = "f026315fb5d833eb5334e75cc27c96413be9e857"
COORDINATION_TREE = "5aa8e800e296f89cfe748941babdbd7c31458d2e"
COORDINATION_CAS_SEQUENCE = 156
COORDINATION_LEDGER_DIGEST = "8fcf5068ca18a4433071f08b82d25b69fc0eb6a1129027533e90dc02dfe9bb98"
CONTEXT_DIGEST = "1058e2792a104f74af0a43844467482a7abb29a99da129c8e0be92b6ea0f922d"
FENCE_DIGEST = "cb123dd654137debce2a0b4679dde737645d30af9b57d52a43ee14aad3f997d2"
PREREQUISITE_DIGEST = "62ea4185d0266ec91ea0df9352645e192869cdbf2924278a08ecdfd3bd75488c"
TRANSITION_DIGEST = "f7b73b37ef4ba4cf4388821b9658cfc49aa5e45fb9188b7d3dd7b0c2704c3072"
HYDRATION_PROJECTION_DIGEST = "74cc810fa233e659d6fe7ea006b39dc1012ead0912f097539e16c2839f6de6a0"
S10_RESERVATION_DIGEST = "274b8e3d9eff11805f5abfec7e1b8a702b91751056f0952e432388c35fe6657a"

SOURCE_PATHS = [
    "FieldEvidenceApp/Domain/InspectionKernel/CompletedActivitySnapshotContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ReportProjectionContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/EvidenceDetailCardContractsV1.swift",
    "FieldEvidenceApp/Domain/Reporting/ContractManifestV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicOpenJSONRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/DeterministicPDFRendererV1.swift",
    "FieldEvidenceApp/Infrastructure/Reporting/ReportProjectionRegistryV1.swift",
    "FieldEvidenceAppTests/V9_16SnapshotProjectionTests.swift",
    "FieldEvidenceAppTests/Fixtures/V21/Contracts/V21P03C06SnapshotProjectionCorpusV1.json",
]
SCRIPT_PATHS = ["Scripts/v23/p03_c06_contracts.py", "Scripts/v23/generate_p03_c06_contracts.py", "Scripts/v23/verify_p03_c06_contracts.py"]
SCHEMA_PATHS = [
    "Scripts/v23/completed-activity-snapshot.schema.json", "Scripts/v23/evidence-detail-card-profile.schema.json",
    "Scripts/v23/evidence-detail-card-render-receipt.schema.json", "Scripts/v23/final-audience-privacy-confirmation.schema.json",
    "Scripts/v23/contract-manifest.schema.json", "Scripts/v23/report-projection-evidence.schema.json",
]
CONTRACT_PATHS = [
    "docs/design/v23/tooling/V23P03C06CompletedSnapshotContractV1.json",
    "docs/design/v23/tooling/V23P03C06EvidenceDetailCardContractV1.json",
    "docs/design/v23/tooling/V23P03C06ContractManifestV1.json",
    "docs/design/v23/tooling/V23P03C06ProjectionContractV1.json",
    "docs/design/v23/tooling/V23P03C06ProjectionEvidenceReceiptV1.json",
]
MANIFEST = "docs/design/v23/tooling/V23-P03-C06-tooling-manifest.json"
FIXTURE = SOURCE_PATHS[-1]
GENERATED_PATHS = SCHEMA_PATHS + CONTRACT_PATHS + [MANIFEST]
TOOL_PATHS = SCRIPT_PATHS + GENERATED_PATHS
PATH_FENCE = SOURCE_PATHS + TOOL_PATHS
EXISTING_PATHS: list[str] = []
NEW_PATHS = PATH_FENCE
MANIFEST_INPUT_PATHS = PATH_FENCE[:-1]
BYTE_NORMALIZATION = "UTF8_TEXT_CRLF_TO_LF_FOR_EVIDENCE_DIGESTS"
EVIDENCE_IDS = [f"{CARD}-{kind}" for kind in ("G01", "A01", "H01", "I01", "R01")]
PRODUCT_SCHEMA_PATHS = SCHEMA_PATHS[:5]
TOOLING_SCHEMA_PATHS = [SCHEMA_PATHS[5]]


class ContractError(ValueError):
    pass


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def pretty(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n").encode()


def digest(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def evidence_bytes(root: Path, relative: str) -> bytes:
    return (root / relative).read_bytes().replace(b"\r\n", b"\n")


def authority() -> dict[str, Any]:
    return {"appBaseHead": APP_BASE_HEAD, "appBaseTree": APP_BASE_TREE, "coordinationHead": COORDINATION_HEAD,
            "coordinationTree": COORDINATION_TREE, "coordinationCASSequence": COORDINATION_CAS_SEQUENCE,
            "coordinationLedgerDigest": COORDINATION_LEDGER_DIGEST, "contextDigest": CONTEXT_DIGEST,
            "fenceDigest": FENCE_DIGEST, "prerequisiteDigest": PREREQUISITE_DIGEST, "transitionDigest": TRANSITION_DIGEST,
            "hydrationProjectionDigest": HYDRATION_PROJECTION_DIGEST, "s10ReservationDigest": S10_RESERVATION_DIGEST}


def field(field_id: str, json_name: str, kind: str, *, required: bool = True, nullable: bool = False,
          reference: str | None = None, element: str | None = None, minimum: int | None = None,
          maximum: int | None = None, maximum_bytes: int | None = None, maximum_items: int | None = None,
          ordered: bool = False, unique: bool = False) -> dict[str, Any]:
    result: dict[str, Any] = {"fieldID": field_id, "jsonName": json_name, "kind": kind, "required": required,
                              "nullable": nullable, "ordered": ordered, "uniqueItems": unique}
    for key, value in (("arrayElementKind", element), ("referencedTypeID", reference),
                       ("minimumInteger", minimum), ("maximumInteger", maximum),
                       ("maximumUTF8Bytes", maximum_bytes), ("maximumItems", maximum_items)):
        if value is not None:
            result[key] = value
    return result


def obj(type_id: str, fields: list[dict[str, Any]]) -> dict[str, Any]:
    return {"typeID": type_id, "version": 1, "unknownFieldPolicy": "REJECT", "fields": sorted(fields, key=lambda x: x["fieldID"])}


def enum(type_id: str, values: list[str]) -> dict[str, Any]:
    return {"typeID": type_id, "version": 1, "policy": "CLOSED", "knownValues": sorted(values)}


def normative_contract_manifest() -> dict[str, Any]:
    def field_id(name: str) -> str:
        words = re.sub(r"(.)([A-Z][a-z]+)", r"\1-\2", name)
        return re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", words).replace("_", "-").lower()

    i = lambda name, **kw: field(field_id(name), name, "STRING", maximum_bytes=kw.pop("maximum_bytes", 128), **kw)
    h = lambda name, **kw: field(field_id(name), name, "SHA256", **kw)
    n = lambda name, **kw: field(field_id(name), name, "INTEGER", **kw)
    b = lambda name, **kw: field(field_id(name), name, "BOOLEAN", **kw)
    e = lambda name, ref, **kw: field(field_id(name), name, "ENUM", reference=ref, **kw)
    o = lambda name, ref, **kw: field(field_id(name), name, "OBJECT", reference=ref, **kw)
    a = lambda name, element, cap, **kw: field(field_id(name), name, "ARRAY", element=element, maximum_items=cap, **kw)
    objects = [
        obj("audience-privacy-policy-v1", [e("audience", "report-audience-v1"), i("policyID"), h("policySHA256"),
            n("policyVersion", minimum=1), a("prohibitedCanaries", "STRING", 256, ordered=True, unique=True),
            n("schemaVersion", minimum=1, maximum=1)]),
        obj("completed-activity-snapshot-payload-v1", [i("amendmentReason", required=False, maximum_bytes=4096),
            field("completed-at", "completedAt", "UTC_INSTANT"), a("evidenceCards", "OBJECT", 256, reference="evidence-detail-card-v1", ordered=True, unique=True),
            field("generated-at", "generatedAt", "UTC_INSTANT"), a("limitations", "STRING", 64, ordered=True, unique=True),
            i("packageReleaseID"), o("profileBinding", "finalized-report-profile-binding-v1"), i("reportID"),
            n("schemaVersion", minimum=1, maximum=1), a("serviceFacts", "OBJECT", 256, reference="completed-service-fact-v1", ordered=True, unique=True),
            i("snapshotID"), n("snapshotRevision", minimum=1), i("sourceActivityID"), n("sourceRevision", minimum=1),
            h("supersededSnapshotSHA256", required=False), i("supersedesSnapshotID", required=False), i("workspaceID")]),
        obj("completed-activity-snapshot-v1", [o("payload", "completed-activity-snapshot-payload-v1"), n("schemaVersion", minimum=1, maximum=1), h("snapshotSHA256")]),
        obj("completed-service-fact-v1", [field("effective-at", "effectiveAt", "UTC_INSTANT", required=False), i("factID"),
            e("kind", "completed-service-fact-kind-v1"), i("label", maximum_bytes=4096), e("privacyClass", "report-privacy-class-v1"), i("value", maximum_bytes=4096)]),
        obj("evidence-detail-card-profile-v1", [e("audience", "report-audience-v1"), o("audiencePrivacyPolicy", "audience-privacy-policy-v1"),
            i("displayProfileID"), a("includedFieldIDs", "STRING", 256, ordered=True, unique=True),
            i("limitationsText", maximum_bytes=4096), i("localeIdentifier", maximum_bytes=64), i("markupProfileID"),
            n("markupProfileVersion", minimum=1), i("outputScopeID"), i("privacyTransformID"), n("privacyTransformVersion", minimum=1),
            i("profileID"), n("profileRelease", minimum=1), i("rendererVersion"), n("schemaVersion", minimum=1, maximum=1)]),
        obj("evidence-detail-card-render-receipt-v1", [e("audience", "report-audience-v1"), i("cardID"), b("captureTimeVerified"),
            h("composedOutputSHA256"), o("confirmation", "final-audience-privacy-confirmation-v1"), i("confirmationID"),
            b("limitationsPresented"), b("locationVerified"), i("outputScopeID"), b("personVerified"), h("privacyTransformSHA256"),
            h("profileSHA256"), i("receiptID"), h("reviewedMarkupSHA256"), n("schemaVersion", minimum=1, maximum=1),
            h("semanticSHA256"), h("semanticTextSHA256"), i("snapshotID"), h("sourceSnapshotSHA256")]),
        obj("evidence-detail-card-v1", [a("annotations", "STRING", 128, ordered=True), e("audience", "report-audience-v1"),
            o("audiencePrivacyPolicy", "audience-privacy-policy-v1"), i("audiencePrivacyPolicyID"), h("audiencePrivacyPolicySHA256"),
            n("audiencePrivacyPolicyVersion", minimum=1), i("cardID"), i("displayProfileID"), i("evidenceID"),
            a("fields", "OBJECT", 256, reference="evidence-detail-field-v1", ordered=True, unique=True), i("limitationsText", maximum_bytes=4096),
            i("localeIdentifier", maximum_bytes=64), i("outputScopeID"), a("outputReferences", "OBJECT", 256, reference="output-scoped-content-reference-v1", ordered=True, unique=True),
            i("privacyTransformID"), n("privacyTransformVersion", minimum=1), h("privacyTransformedSHA256"),
            o("profile", "evidence-detail-card-profile-v1"), i("profileID"), h("profileSHA256"),
            a("referenceLabels", "STRING", 256, ordered=True), i("rendererVersion"), i("reviewedMarkupID"),
            o("reviewedMarkup", "reviewed-evidence-markup-v1"), h("reviewedMarkupSHA256"),
            n("schemaVersion", minimum=1, maximum=1), i("workspaceID")]),
        obj("evidence-detail-field-v1", [i("fieldID"), i("label", maximum_bytes=4096), e("sensitivity", "evidence-detail-sensitivity-v1"), i("value", maximum_bytes=4096)]),
        obj("final-audience-privacy-confirmation-v1", [b("approvalVerified"), e("audience", "report-audience-v1"), i("audiencePrivacyPolicyID"),
            h("audiencePrivacyPolicySHA256"), n("audiencePrivacyPolicyVersion", minimum=1), o("card", "evidence-detail-card-v1"),
            h("cardSHA256"), b("captureTimeVerified"), h("composedOutputSHA256"), i("confirmationID"),
            o("detection", "post-markup-audience-privacy-detection-v1"), i("detectorID"),
            e("detectorDisposition", "audience-privacy-detector-disposition-v1"), n("detectorVersion", minimum=1), i("displayProfileID"),
            b("deliveryVerified"), b("historicalRewriteClaimed"), i("localeIdentifier", maximum_bytes=64), b("locationVerified"),
            i("outputScopeID"), b("personVerified"), b("privacyTransformAppliedBeforeMarkup"), h("privacyTransformSHA256"),
            i("profileID"), h("profileSHA256"), i("rendererVersion"), h("reviewedMarkupSHA256"), n("schemaVersion", minimum=1, maximum=1),
            b("securityVerified"), h("semanticSHA256"), h("semanticTextSHA256"), h("sourceSnapshotSHA256"),
            b("userConfirmedExactComposedBytes"), i("workspaceID")]),
        obj("finalized-report-profile-binding-v1", [e("audience", "report-audience-v1"), i("contractManifestID"), h("contractManifestSHA256"),
            n("contractManifestVersion", minimum=1), i("displayProfileID"), e("detail", "report-detail-level-v1"), i("exportProfileID"),
            n("exportProfileRelease", minimum=1), h("exportProfileSHA256"), i("localeIdentifier", maximum_bytes=64), e("mediaLayout", "report-media-layout-v1"),
            e("orientation", "report-orientation-v1"), i("outputScopeID"), i("privacyTransformID"), i("projectionVersion"), i("rendererVersion"),
            i("reportProfileID"), n("reportProfileRelease", minimum=1), h("reportProfileSHA256"), n("schemaVersion", minimum=1, maximum=1),
            a("sectionIDs", "STRING", 64, ordered=True, unique=True), i("sectionRegistryID"), h("sectionRegistrySHA256"),
            n("sectionRegistryVersion", minimum=1), i("snapshotID"), i("unitsProfileID"), i("workspaceID")]),
        obj("output-scoped-content-reference-v1", [e("byteRole", "content-byte-role-v1"), h("contentSHA256"), i("mediaType", maximum_bytes=4096),
            i("outputReferenceID"), i("outputScopeID"), h("workspaceBindingSHA256")]),
        obj("post-markup-audience-privacy-detection-v1", [e("audience", "report-audience-v1"), h("cardSHA256"),
            field("composed-output", "composedOutput", "BASE64_BYTES", maximum_bytes=8388608), h("composedOutputSHA256"),
            i("detectorID"), n("detectorVersion", minimum=1), e("disposition", "audience-privacy-detector-disposition-v1"),
            a("findingKinds", "ENUM", 4, reference="audience-privacy-finding-kind-v1", ordered=True, unique=True),
            i("policyID"), h("policySHA256"), n("policyVersion", minimum=1), n("schemaVersion", minimum=1, maximum=1),
            i("semanticText", maximum_bytes=4096), h("semanticTextSHA256")]),
        obj("reviewed-evidence-markup-v1", [i("markupID"), a("orderedAnnotations", "STRING", 128, ordered=True),
            a("orderedReferenceLabels", "STRING", 256, ordered=True), h("sourcePrivacyDigest")]),
        obj("report-section-definition-v1", [n("order", minimum=0), e("privacyClass", "report-privacy-class-v1"), b("required"),
            b("requiresHeading"), b("requiresTextAlternative"), i("sectionID"),
            a("supportedFormats", "ENUM", 6, reference="report-projection-format-v1", ordered=True, unique=True), n("version", minimum=1)]),
        obj("report-section-registry-v1", [i("registryID"), n("registryVersion", minimum=1), n("schemaVersion", minimum=1, maximum=1),
            a("sections", "OBJECT", 64, reference="report-section-definition-v1", ordered=True, unique=True)]),
        obj("contract-codec-rule-v1", [i("binaryEncoding"), i("canonicalJSON"), n("codecVersion", minimum=1, maximum=1), b("formatAssertion"),
            i("integerEncoding"), i("nullEncoding"), i("stringNormalization"), i("timeEncoding")]),
        obj("contract-compatibility-rule-v1", [n("maximumReaderVersion", minimum=1), n("minimumReaderVersion", minimum=1),
            b("publishedVersionsImmutable"), e("unknownObjectFields", "contract-unknown-field-policy-v1")]),
        obj("contract-enum-definition-v1", [a("knownValues", "STRING", 512, ordered=True, unique=True),
            e("policy", "contract-enum-policy-v1"), i("typeID"), n("version", minimum=1)]),
        obj("contract-field-definition-v1", [e("arrayElementKind", "contract-scalar-kind-v1", required=False), i("fieldID"),
            i("jsonName"), e("kind", "contract-scalar-kind-v1"), n("maximumInteger", required=False),
            n("maximumItems", required=False, minimum=1), n("maximumUTF8Bytes", required=False, minimum=1),
            n("minimumInteger", required=False), b("nullable"), b("ordered"), i("referencedTypeID", required=False),
            b("required"), b("uniqueItems")]),
        obj("contract-manifest-v1", [o("codec", "contract-codec-rule-v1"),
            o("compatibility", "contract-compatibility-rule-v1"),
            a("enums", "OBJECT", 256, reference="contract-enum-definition-v1", ordered=True, unique=True),
            i("manifestID"), n("manifestVersion", minimum=1),
            a("objects", "OBJECT", 512, reference="contract-object-definition-v1", ordered=True, unique=True),
            i("persistentContractSchema"), o("reportSectionRegistry", "report-section-registry-v1"),
            n("schemaVersion", minimum=1, maximum=1)]),
        obj("contract-object-definition-v1", [a("fields", "OBJECT", 512, reference="contract-field-definition-v1", ordered=True, unique=True),
            i("typeID"), e("unknownFieldPolicy", "contract-unknown-field-policy-v1"), n("version", minimum=1)]),
        obj("contract-schema-derivation-receipt-v1", [i("independentInstanceValidationOwner"), h("manifestSHA256"),
            b("officialMetaSchemaValid"), i("receiptID"), b("releaseDependencyAdded"), b("repeatedGenerationByteIdentical"),
            n("schemaVersion", minimum=1, maximum=1), h("schemaSHA256")]),
        obj("export-profile-v1", [i("exportProfileID"), n("exportProfileRelease", minimum=1),
            a("formats", "ENUM", 6, reference="report-projection-format-v1", ordered=True, unique=True),
            n("maximumArchiveBytes", minimum=1, maximum=8388608), n("maximumMediaItems", minimum=0, maximum=256),
            e("packaging", "report-packaging-v1"), i("privacyTransformID"), n("schemaVersion", minimum=1, maximum=1)]),
        obj("open-json-schema-projection-v1", [i("dialect", maximum_bytes=4096), i("manifestID"), h("manifestSHA256"),
            n("manifestVersion", minimum=1), b("networkFetchRequired"), i("schemaID", maximum_bytes=4096),
            n("schemaVersion", minimum=1, maximum=1), h("schemaSHA256")]),
        obj("report-layout-profile-v1", [e("audience", "report-audience-v1"), e("detail", "report-detail-level-v1"),
            i("displayProfileID"), i("localeIdentifier", maximum_bytes=64), e("mediaLayout", "report-media-layout-v1"),
            e("orientation", "report-orientation-v1"), i("profileID"), n("profileRelease", minimum=1),
            n("schemaVersion", minimum=1, maximum=1), a("sectionIDs", "STRING", 64, ordered=True, unique=True), i("unitsProfileID")]),
        obj("report-preview-projection-v1", [b("hasMetricEffect"), b("hasReportEffect"), b("hasShareEffect"),
            b("markedPreview"), i("previewID"), h("profileSHA256"), n("schemaVersion", minimum=1, maximum=1),
            n("sourceRevision", minimum=1)]),
        obj("report-projection-registry-v1", [b("acceptanceCredit"), b("adoptionEnabled"), i("downgradeDisposition"),
            b("hostedDispatchRan"), b("nativeCompileRan"), i("persistentContractSchema"), i("registryID"), b("releaseCredit"),
            b("requiresAcceptedS10_6Reconciliation"), a("requiredFormats", "ENUM", 6, reference="report-projection-format-v1", ordered=True, unique=True),
            n("schemaVersion", minimum=1, maximum=1), i("soleRenderer")]),
        obj("report-semantic-node-v1", [i("label", maximum_bytes=4096), i("outputReferenceID", required=False),
            i("role"), i("sectionID"), i("semanticID"), i("value", maximum_bytes=4096)]),
        obj("report-semantic-projection-v1", [h("manifestSHA256"),
            a("nodes", "OBJECT", 512, reference="report-semantic-node-v1", ordered=True, unique=True),
            h("profileBindingSHA256"), i("projectionVersion"), n("schemaVersion", minimum=1, maximum=1),
            h("semanticSHA256"), h("snapshotSHA256"), i("snapshotID")]),
    ]
    enums = [
        enum("audience-privacy-detector-disposition-v1", ["BLOCKED", "PASS"]),
        enum("audience-privacy-finding-kind-v1", ["PROHIBITED_ANNOTATION", "PROHIBITED_FIELD", "PROHIBITED_REFERENCE_LABEL", "PROHIBITED_SEMANTIC_TEXT"]),
        enum("completed-service-fact-kind-v1", ["SERVICE_HISTORY", "SERVICE_REQUEST", "SERVICE_STATUS"]),
        enum("content-byte-role-v1", ["DERIVATIVE", "IMMUTABLE_ORIGINAL"]),
        enum("evidence-detail-sensitivity-v1", ["AUDIENCE_SAFE", "CAPABILITY_SECRET", "CONTACT_DATA", "DIAGNOSTIC", "DIRECT_COST", "LOCAL_IDENTIFIER", "ORIGINAL_MEDIA", "PRIVATE_NOTE"]),
        enum("report-audience-v1", ["CUSTOMER_SAFE", "INTERNAL"]), enum("report-detail-level-v1", ["COMPLETE", "SUMMARY"]),
        enum("report-media-layout-v1", ["COMPACT_GRID", "FULL_WIDTH", "NONE", "STANDARD_GRID"]),
        enum("report-orientation-v1", ["LANDSCAPE", "PORTRAIT"]),
        enum("report-privacy-class-v1", ["AUDIENCE_SAFE", "INTERNAL_ONLY", "MANDATORY_PUBLIC_TRUTH"]),
        enum("report-projection-format-v1", ["FORMULA_SAFE_CSV", "MANIFEST", "MEDIA", "OPEN_JSON", "PDF", "STRUCTURED_TEXT"]),
        enum("contract-enum-policy-v1", ["CLOSED", "PRESERVE_UNKNOWN"]),
        enum("contract-scalar-kind-v1", ["ARRAY", "BASE64_BYTES", "BOOLEAN", "ENUM", "INTEGER", "OBJECT", "SHA256", "STRING", "UTC_INSTANT"]),
        enum("contract-unknown-field-policy-v1", ["PRESERVE", "REJECT"]),
        enum("report-packaging-v1", ["COMBINED", "SEPARATE_PER_WORK_ITEM"]),
    ]
    formats = ["OPEN_JSON", "PDF", "STRUCTURED_TEXT"]
    rows = [("identity", True, "MANDATORY_PUBLIC_TRUTH"), ("service", False, "AUDIENCE_SAFE"),
            ("evidence", False, "AUDIENCE_SAFE"), ("limitations", True, "MANDATORY_PUBLIC_TRUTH"),
            ("provenance", True, "MANDATORY_PUBLIC_TRUTH"), ("supersession", True, "MANDATORY_PUBLIC_TRUTH"),
            ("manifest", True, "MANDATORY_PUBLIC_TRUTH")]
    sections = [{"sectionID": sid, "version": 1, "required": req, "supportedFormats": formats, "privacyClass": privacy,
                 "requiresHeading": True, "requiresTextAlternative": True, "order": order} for order, (sid, req, privacy) in enumerate(rows)]
    return {"schemaVersion": 1, "manifestID": "v23-p03-c06-contract-manifest-v1", "manifestVersion": 1,
            "persistentContractSchema": "KERNEL_SNAPSHOT_V1",
            "codec": {"codecVersion": 1, "canonicalJSON": "UTF8_SORTED_KEYS_NO_INSIGNIFICANT_WHITESPACE",
                      "binaryEncoding": "RFC4648_BASE64_PADDED",
                      "integerEncoding": "BASE10_INTEGER_NO_EXPONENT", "timeEncoding": "UTC_RFC3339_MILLISECONDS_Z",
                      "nullEncoding": "EXPLICIT_NULL_ONLY_WHEN_REQUIRED_NULLABLE",
                      "stringNormalization": "NFC_WITH_C0_C1_BIDI_CONTROLS_AND_NONCHARACTERS_REJECTED", "formatAssertion": False},
            "compatibility": {"minimumReaderVersion": 1, "maximumReaderVersion": 1, "unknownObjectFields": "REJECT", "publishedVersionsImmutable": True},
            "objects": sorted(objects, key=lambda x: x["typeID"]), "enums": sorted(enums, key=lambda x: x["typeID"]),
            "reportSectionRegistry": {"schemaVersion": 1, "registryID": "v23-p03-c06-report-sections-v1", "registryVersion": 1, "sections": sections}}


def text_shape(maximum_bytes: int | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {"type": "string", "minLength": 1,
                              "pattern": r"^[^\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069\ufffe\uffff]*$",
                              "x_assetrounds_requiresNFC": True,
                              "x_assetrounds_noncharacterPolicy": "REJECT_ALL_UNICODE_NONCHARACTERS",
                              "x_assetrounds_forbiddenUnicodeScalarClasses": ["C0", "C1", "BIDI_CONTROL", "NONCHARACTER"]}
    if maximum_bytes is not None:
        result.update({"maxLength": maximum_bytes, "x_assetrounds_maximumUTF8Bytes": maximum_bytes,
                       "x_assetrounds_maxLengthSemantics": "SOUND_CODE_POINT_CEILING_NOT_UTF8_BYTE_PARITY"})
    return result


def schema_root_type_id(path: str) -> str:
    name = Path(path).name
    suffix = ".schema.json"
    if not name.endswith(suffix):
        raise ContractError(f"invalid product schema path: {path}")
    return name[:-len(suffix)] + "-v1"


def swift_title(type_id: str) -> str:
    return "".join(part.upper() if part in {"id", "json", "pdf", "sha256", "utf8"} else part.capitalize()
                   for part in type_id.split("-"))


def compile_product_schema(manifest: dict[str, Any], path: str) -> dict[str, Any]:
    root_type_id = schema_root_type_id(path)
    objects = {x["typeID"]: x for x in manifest["objects"]}
    enums = {x["typeID"]: x for x in manifest["enums"]}

    def scalar(kind: str, ref: str | None, definition: dict[str, Any]) -> dict[str, Any]:
        if kind == "STRING": return text_shape(definition.get("maximumUTF8Bytes"))
        if kind == "BASE64_BYTES":
            maximum_decoded = definition.get("maximumUTF8Bytes")
            value: dict[str, Any] = {"type": "string", "minLength": 4, "contentEncoding": "base64",
                                     "pattern": r"^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$"}
            if maximum_decoded is not None:
                value.update({"maxLength": ((maximum_decoded + 2) // 3) * 4,
                              "x_assetrounds_maximumDecodedBytes": maximum_decoded,
                              "x_assetrounds_maximumEncodedUTF8Bytes": ((maximum_decoded + 2) // 3) * 4})
            return value
        if kind == "BOOLEAN": return {"type": "boolean"}
        if kind == "UTC_INSTANT": return {"type": "string", "pattern": r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"}
        if kind == "SHA256": return {"type": "string", "pattern": "^[0-9a-f]{64}$"}
        if kind == "INTEGER":
            value: dict[str, Any] = {"type": "integer"}
            if "minimumInteger" in definition: value["minimum"] = definition["minimumInteger"]
            if "maximumInteger" in definition: value["maximum"] = definition["maximumInteger"]
            return value
        if kind in ("OBJECT", "ENUM") and ref:
            return {"$ref": f"#/$defs/{ref}"}
        raise ContractError(f"unresolved manifest kind/reference: {kind}/{ref}")

    def shape(definition: dict[str, Any]) -> dict[str, Any]:
        props: dict[str, Any] = {}; required: list[str] = []
        for item in definition["fields"]:
            if item["kind"] == "ARRAY":
                value = {"type": "array", "maxItems": item["maximumItems"],
                         "items": scalar(item["arrayElementKind"], item.get("referencedTypeID"), item),
                         "x_assetrounds_ordered": item["ordered"]}
                ordering_keys = {
                    ("contract-manifest-v1", "objects"): "typeID", ("contract-manifest-v1", "enums"): "typeID",
                    ("contract-object-definition-v1", "fields"): "fieldID",
                    ("contract-enum-definition-v1", "knownValues"): "LEXICOGRAPHIC",
                    ("report-section-registry-v1", "sections"): "order",
                    ("report-section-definition-v1", "supportedFormats"): "RAW_VALUE",
                }
                if (definition["typeID"], item["jsonName"]) in ordering_keys:
                    value["x_assetrounds_orderingKey"] = ordering_keys[(definition["typeID"], item["jsonName"])]
                if item["uniqueItems"]: value["uniqueItems"] = True
            else:
                value = scalar(item["kind"], item.get("referencedTypeID"), item)
            if item["nullable"]: value = {"anyOf": [value, {"type": "null"}]}
            props[item["jsonName"]] = value
            if item["required"]: required.append(item["jsonName"])
        return {"type": "object", "additionalProperties": False, "properties": props, "required": sorted(required)}

    if root_type_id not in objects: raise ContractError(f"missing root type: {root_type_id}")
    defs = {key: shape(value) for key, value in sorted(objects.items())}
    defs.update({key: {"type": "string", "enum": value["knownValues"]} for key, value in sorted(enums.items())})
    field_def = defs["contract-field-definition-v1"]

    def forbids(*names: str) -> dict[str, Any]:
        return {"not": {"anyOf": [{"required": [name]} for name in names]}}

    field_def["allOf"] = [
        {"if": {"required": ["nullable"], "properties": {"nullable": {"const": True}}},
         "then": {"properties": {"required": {"const": True}}}},
        {"if": {"required": ["kind"], "properties": {"kind": {"const": "ARRAY"}}},
         "then": {"required": ["arrayElementKind", "maximumItems"],
                  "properties": {"arrayElementKind": {"not": {"const": "ARRAY"}}},
                  **forbids("minimumInteger", "maximumInteger", "maximumUTF8Bytes")},
         "else": {"properties": {"ordered": {"const": False}, "uniqueItems": {"const": False}},
                  **forbids("arrayElementKind", "maximumItems")}},
        {"if": {"required": ["kind"], "properties": {"kind": {"enum": ["OBJECT", "ENUM"]}}},
         "then": {"required": ["referencedTypeID"]}},
        {"if": {"required": ["kind"], "properties": {"kind": {"const": "ARRAY"},
                                                        "arrayElementKind": {"enum": ["OBJECT", "ENUM"]}}},
         "then": {"required": ["referencedTypeID"]}},
        {"if": {"required": ["kind"], "properties": {"kind": {"enum": ["BASE64_BYTES", "BOOLEAN", "INTEGER", "SHA256", "STRING", "UTC_INSTANT"]}}},
         "then": forbids("referencedTypeID")},
        {"if": {"required": ["kind", "arrayElementKind"], "properties": {"kind": {"const": "ARRAY"},
                         "arrayElementKind": {"enum": ["BASE64_BYTES", "BOOLEAN", "INTEGER", "SHA256", "STRING", "UTC_INSTANT"]}}},
         "then": forbids("referencedTypeID")},
        {"if": {"required": ["kind"], "properties": {"kind": {"const": "INTEGER"}}},
         "else": forbids("minimumInteger", "maximumInteger")},
        {"if": {"required": ["kind"], "properties": {"kind": {"enum": ["STRING", "BASE64_BYTES"]}}},
         "else": forbids("maximumUTF8Bytes")},
    ]
    field_def["properties"]["fieldID"]["pattern"] = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"
    field_def["properties"]["jsonName"]["pattern"] = r"^[A-Za-z][A-Za-z0-9_]*$"
    field_def["x_assetrounds_integerBoundOrder"] = "minimumInteger <= maximumInteger when both are present"
    root = shape(objects[root_type_id])
    root.update({"$schema": "https://json-schema.org/draft/2020-12/schema",
                 "$id": f"https://schemas.assetrounds.local/v23/p03/c06/{root_type_id}/schema", "title": swift_title(root_type_id),
                 "$defs": defs, "x_assetrounds_manifestID": manifest["manifestID"],
                 "x_assetrounds_manifestVersion": manifest["manifestVersion"],
                 "x_assetrounds_normativeManifestPath": CONTRACT_PATHS[2],
                 "x_assetrounds_productManifestDerived": True,
                 "x_assetrounds_rootTypeID": root_type_id, "x_assetrounds_schemaClass": "PRODUCT_CONTRACT"})
    return root


def strict_object(properties: dict[str, Any], required: list[str] | None = None) -> dict[str, Any]:
    return {"type": "object", "additionalProperties": False, "properties": properties,
            "required": list(properties) if required is None else required}


def evidence_schema() -> dict[str, Any]:
    sha = {"type": "string", "pattern": "^[0-9a-f]{64}$"}
    root = strict_object({"schemaVersion": {"const": 1}, "receiptID": {"const": "v23-p03-c06-static-receipt"},
                          "cardID": {"const": CARD},
                          "byteNormalization": {"const": BYTE_NORMALIZATION},
                          "registrySHA256": sha, "fixtureSHA256": sha,
                          "sourceArtifacts": {"type": "array", "minItems": 9, "maxItems": 9,
                                              "items": strict_object({"path": text_shape(256), "sha256": sha})},
                          "evidenceIDs": {"const": EVIDENCE_IDS}, "result": {"const": "PASS"},
                          "verificationMode": {"const": "STATIC_ONLY"}, "nativeCompileRan": {"const": False},
                          "hostedDispatchRan": {"const": False}, "hostedDispatchEnabled": {"const": False},
                          "acceptanceEnabled": {"const": False}, "acceptanceCredit": {"const": False},
                          "releaseReady": {"const": False}, "releaseCredit": {"const": False},
                          "requiresAcceptedS10_6Reconciliation": {"const": True}})
    root.update({"$schema": "https://json-schema.org/draft/2020-12/schema",
                 "$id": "https://schemas.assetrounds.local/v23/p03/c06/report-projection-evidence/v1",
                 "title": "ProvisionalP03C06ProjectionEvidenceReceiptV1",
                 "x_assetrounds_productManifestDerived": False,
                 "x_assetrounds_schemaClass": "OPERATIONAL_EVIDENCE_TOOLING"})
    return root


def schemas() -> dict[str, dict[str, Any]]:
    manifest = normative_contract_manifest()
    values = {path: compile_product_schema(manifest, path) for path in PRODUCT_SCHEMA_PATHS}
    values[TOOLING_SCHEMA_PATHS[0]] = evidence_schema()
    return values


def sample_instances(fixture: dict[str, Any]) -> dict[str, dict[str, Any]]:
    seed = fixture["schemaSampleSeeds"]
    sha = seed["sha256"]
    composed_output = seed["semanticText"].encode("utf-8")
    composed_output_sha = digest(composed_output)
    policy = {"schemaVersion": 1, "policyID": "customer-safe-policy-v1", "policyVersion": 1,
              "audience": seed["audience"], "prohibitedCanaries": sorted(fixture["privacyCanaries"]), "policySHA256": sha}
    profile = {"schemaVersion": 1, "profileID": "evidence-profile-v1", "profileRelease": 1,
               "audience": seed["audience"], "outputScopeID": "output-scope-a", "privacyTransformID": "privacy-v1",
               "privacyTransformVersion": 1, "markupProfileID": "markup-profile-v1", "markupProfileVersion": 1,
               "localeIdentifier": "en_US", "displayProfileID": "display-v1", "rendererVersion": "renderer-v1",
               "audiencePrivacyPolicy": policy, "includedFieldIDs": ["service-status"],
               "limitationsText": "Evidence detail does not verify capture time, location, or person."}
    markup = {"markupID": "markup-a", "sourcePrivacyDigest": sha,
              "orderedAnnotations": ["Reviewed output"], "orderedReferenceLabels": ["Customer-safe derivative"]}
    card = {"schemaVersion": 1, "cardID": "card-a", "workspaceID": seed["workspaceID"], "evidenceID": "evidence-a",
            "outputScopeID": "output-scope-a", "profileID": profile["profileID"], "profileSHA256": sha, "profile": profile,
            "audience": seed["audience"], "privacyTransformID": "privacy-v1", "privacyTransformVersion": 1,
            "localeIdentifier": "en_US", "displayProfileID": "display-v1", "rendererVersion": "renderer-v1",
            "audiencePrivacyPolicyID": policy["policyID"], "audiencePrivacyPolicyVersion": 1,
            "audiencePrivacyPolicySHA256": sha, "audiencePrivacyPolicy": policy, "privacyTransformedSHA256": sha,
            "reviewedMarkupID": markup["markupID"], "reviewedMarkupSHA256": sha, "reviewedMarkup": markup,
            "fields": [{"fieldID": "service-status", "label": "Service status", "value": "Scheduled", "sensitivity": "AUDIENCE_SAFE"}],
            "outputReferences": [{"outputScopeID": "output-scope-a", "outputReferenceID": "reference-a",
                                  "workspaceBindingSHA256": sha, "contentSHA256": sha, "mediaType": "image/jpeg", "byteRole": "DERIVATIVE"}],
            "annotations": markup["orderedAnnotations"], "referenceLabels": markup["orderedReferenceLabels"],
            "limitationsText": profile["limitationsText"]}
    detection = {"schemaVersion": 1, "detectorID": "detector-v1", "detectorVersion": 1,
                 "audience": seed["audience"], "policyID": policy["policyID"], "policyVersion": 1,
                 "policySHA256": sha, "cardSHA256": sha, "semanticText": seed["semanticText"],
                 "semanticTextSHA256": sha, "composedOutput": base64.b64encode(composed_output).decode("ascii"),
                 "composedOutputSHA256": composed_output_sha, "disposition": "PASS", "findingKinds": []}
    confirmation = {"schemaVersion": 1, "confirmationID": "confirmation-a", "workspaceID": seed["workspaceID"],
                    "outputScopeID": "output-scope-a", "profileID": profile["profileID"], "sourceSnapshotSHA256": sha,
                    "profileSHA256": sha, "privacyTransformSHA256": sha, "reviewedMarkupSHA256": sha,
                    "semanticSHA256": sha, "semanticTextSHA256": sha, "cardSHA256": sha, "card": card,
                    "audience": seed["audience"], "localeIdentifier": "en_US", "displayProfileID": "display-v1",
                    "rendererVersion": "renderer-v1", "audiencePrivacyPolicyID": policy["policyID"],
                    "audiencePrivacyPolicyVersion": 1, "audiencePrivacyPolicySHA256": sha, "composedOutputSHA256": composed_output_sha,
                    "privacyTransformAppliedBeforeMarkup": True, "userConfirmedExactComposedBytes": True,
                    "detectorID": "detector-v1", "detectorVersion": 1, "detectorDisposition": "PASS", "detection": detection,
                    "captureTimeVerified": False, "locationVerified": False, "personVerified": False,
                    "deliveryVerified": False, "approvalVerified": False, "securityVerified": False, "historicalRewriteClaimed": False}
    receipt = {"schemaVersion": 1, "receiptID": "receipt-a", "snapshotID": "snapshot-a", "cardID": "card-a",
               "outputScopeID": "output-scope-a", "audience": seed["audience"], "sourceSnapshotSHA256": sha,
               "profileSHA256": sha, "privacyTransformSHA256": sha, "reviewedMarkupSHA256": sha,
               "semanticSHA256": sha, "semanticTextSHA256": sha, "composedOutputSHA256": composed_output_sha,
               "confirmationID": "confirmation-a", "confirmation": confirmation, "limitationsPresented": True,
               "captureTimeVerified": False, "locationVerified": False, "personVerified": False}
    binding = {"schemaVersion": 1, "workspaceID": seed["workspaceID"], "snapshotID": "snapshot-a",
               "outputScopeID": "output-scope-a", "reportProfileID": "report-profile-v1", "reportProfileRelease": 1,
               "reportProfileSHA256": sha, "exportProfileID": "export-profile-v1", "exportProfileRelease": 1,
               "exportProfileSHA256": sha, "sectionRegistryID": "section-registry-v1", "sectionRegistryVersion": 1,
               "sectionRegistrySHA256": sha, "contractManifestID": "contract-manifest-v1", "contractManifestVersion": 1,
               "contractManifestSHA256": sha, "sectionIDs": ["identity", "limitations", "manifest", "provenance", "supersession"],
               "audience": seed["audience"], "detail": "COMPLETE", "privacyTransformID": "privacy-v1",
               "localeIdentifier": "en_US", "unitsProfileID": "units-v1", "displayProfileID": "display-v1",
               "orientation": "PORTRAIT", "mediaLayout": "STANDARD_GRID", "rendererVersion": "renderer-v1",
               "projectionVersion": "projection-v1"}
    payload = {"schemaVersion": 1, "workspaceID": seed["workspaceID"], "snapshotID": "snapshot-a", "snapshotRevision": 1,
               "sourceActivityID": "activity-a", "sourceRevision": 1, "reportID": "report-a", "packageReleaseID": "package-v1",
               "generatedAt": "2026-08-27T00:00:00.000Z", "completedAt": "2026-08-27T00:00:00.000Z",
               "profileBinding": binding, "serviceFacts": [{"factID": "service-status", "kind": "SERVICE_STATUS",
               "privacyClass": "AUDIENCE_SAFE", "label": "Service status", "value": "Scheduled"}],
               "evidenceCards": [card], "limitations": ["Projection facts are frozen from the completed activity."]}
    snapshot = {"schemaVersion": 1, "payload": payload, "snapshotSHA256": sha}
    return {SCHEMA_PATHS[0]: snapshot, SCHEMA_PATHS[1]: profile, SCHEMA_PATHS[2]: receipt, SCHEMA_PATHS[3]: confirmation}


def negative_sample_instances(fixture: dict[str, Any]) -> list[dict[str, Any]]:
    positives = sample_instances(fixture)
    manifest = normative_contract_manifest()

    def mutated_field(type_id: str, json_name: str) -> tuple[dict[str, Any], dict[str, Any]]:
        value = copy.deepcopy(manifest)
        definition = next(item for item in value["objects"] if item["typeID"] == type_id)
        return value, next(item for item in definition["fields"] if item["jsonName"] == json_name)

    explicit_null = copy.deepcopy(positives[SCHEMA_PATHS[0]])
    explicit_null["payload"]["amendmentReason"] = None
    array_missing_kind, array_field = mutated_field("contract-manifest-v1", "objects")
    del array_field["arrayElementKind"]
    object_missing_reference, object_field = mutated_field("contract-manifest-v1", "codec")
    del object_field["referencedTypeID"]
    scalar_array_metadata, scalar_array_field = mutated_field("contract-codec-rule-v1", "canonicalJSON")
    scalar_array_field["maximumItems"] = 2
    scalar_reference, scalar_reference_field = mutated_field("contract-codec-rule-v1", "canonicalJSON")
    scalar_reference_field["referencedTypeID"] = "contract-codec-rule-v1"
    enum_array_unknown = copy.deepcopy(manifest)
    enum_array_unknown["reportSectionRegistry"]["sections"][0]["supportedFormats"].append("UNKNOWN")
    invalid_base64 = copy.deepcopy(positives[SCHEMA_PATHS[3]])
    invalid_base64["detection"]["composedOutput"] = "***not-base64***"
    return [
        {"label": "ARRAY_MISSING_ELEMENT_KIND", "schemaPath": SCHEMA_PATHS[4], "instance": array_missing_kind},
        {"label": "BASE64_INVALID_ENCODING", "schemaPath": SCHEMA_PATHS[3], "instance": invalid_base64},
        {"label": "ENUM_ARRAY_UNKNOWN_VALUE", "schemaPath": SCHEMA_PATHS[4], "instance": enum_array_unknown},
        {"label": "EXPLICIT_NULL_OPTIONAL", "schemaPath": SCHEMA_PATHS[0], "instance": explicit_null},
        {"label": "OBJECT_MISSING_REFERENCE", "schemaPath": SCHEMA_PATHS[4], "instance": object_missing_reference},
        {"label": "SCALAR_HAS_ARRAY_METADATA", "schemaPath": SCHEMA_PATHS[4], "instance": scalar_array_metadata},
        {"label": "SCALAR_HAS_REFERENCE", "schemaPath": SCHEMA_PATHS[4], "instance": scalar_reference},
    ]


def sealed_document(document: dict[str, Any]) -> dict[str, Any]:
    result = dict(document)
    result["artifactDigest"] = digest(pretty(result))
    return result


def base_document(kind: str, owned: list[str], invariants: list[str], failures: list[str]) -> dict[str, Any]:
    return sealed_document({"schema": kind, "schemaVersion": 1, "cardID": CARD, "authority": authority(),
                            "ownedContracts": owned, "invariants": invariants, "failureCases": failures,
                            "persistentChangeMode": "DECLARATION_ONLY", "persistentContractSchema": "KERNEL_SNAPSHOT_V1",
                            "exportReportRequired": True, "downgradeDisposition": "DORMANT_REVERT_ALLOWED",
                            "verificationMode": "STATIC_ONLY", "nativeCompileRan": False, "hostedDispatchRan": False,
                            "hostedDispatchEnabled": False, "adoptionEnabled": False, "acceptanceEnabled": False,
                            "acceptanceCredit": False, "releaseReady": False, "releaseCredit": False,
                            "phase10PollingDuringParallelExecution": False, "nativeOrHostedEvidenceClaimed": False,
                            "acceptanceOrReleaseClaimed": False, "requiresAcceptedS10_6Reconciliation": True})


def contract_documents(root: Path) -> dict[str, dict[str, Any]]:
    documents = {
        CONTRACT_PATHS[0]: base_document("V23P03C06CompletedSnapshotContractV1", ["CompletedActivitySnapshotV1", "FinalizedReportProfileBindingV1"],
            ["IMMUTABLE_HASH_BOUND_PAYLOAD", "AMENDMENT_CREATES_NEW_LINKED_SNAPSHOT", "HISTORIC_BYTES_NEVER_REWRITTEN"],
            ["DIGEST_MISMATCH", "FORK_OR_GAP", "IN_PLACE_REWRITE"]),
        CONTRACT_PATHS[1]: base_document("V23P03C06EvidenceDetailCardContractV1",
            ["EvidenceDetailCardProfileV1", "EvidenceDetailCardRenderReceiptV1", "FinalAudiencePrivacyConfirmationV1", "PostMarkupAudiencePrivacyDetectionV1"],
            ["PRIVACY_TRANSFORM_BEFORE_REVIEWED_MARKUP", "CUSTOMER_SAFE_CANARIES_EXCLUDED", "OUTPUT_SCOPED_WORKSPACE_BOUND_REFERENCES_ONLY",
             "SEMANTIC_TEXT_DIGEST_BOUND", "CAPTURE_TIME_LOCATION_PERSON_NOT_VERIFIED"],
            ["FORGED_CONFIRMATION", "PRIVACY_CANARY_LEAK", "STALE_COMPOSED_BYTES"]),
        CONTRACT_PATHS[2]: normative_contract_manifest(),
        CONTRACT_PATHS[3]: base_document("V23P03C06ProjectionContractV1",
            ["ReportSemanticProjectionV1", "ReportLayoutProfileV1", "ExportProfileV1", "ReportPreviewProjectionV1"],
            ["ONE_SEMANTIC_RENDERER", "PDF_OPEN_JSON_TEXT_PARITY", "STRUCTURED_TEXT_ALWAYS_PRESENT", "TAGGED_PDF_NOT_CLAIMED", "REPEAT_RENDER_BYTE_EQUAL"],
            ["HOSTILE_TEXT", "NONDETERMINISTIC_BYTES", "PROJECTION_DISAGREEMENT", "UNSUPPORTED_ACCESSIBILITY_CLAIM"]),
    }
    registry = canonical({"declaredContracts": ["CompletedActivitySnapshotV1", "EvidenceDetailCardProfileV1",
        "EvidenceDetailCardRenderReceiptV1", "FinalAudiencePrivacyConfirmationV1", "ContractManifestV1", "ReportProjectionRegistryV1"],
        "downgradeDisposition": "DORMANT_REVERT_ALLOWED", "persistentContractSchema": "KERNEL_SNAPSHOT_V1", "schemaVersion": 1})
    documents[CONTRACT_PATHS[4]] = {"schemaVersion": 1, "receiptID": "v23-p03-c06-static-receipt", "cardID": CARD,
        "byteNormalization": BYTE_NORMALIZATION,
        "registrySHA256": digest(registry), "fixtureSHA256": digest(evidence_bytes(root, FIXTURE)),
        "sourceArtifacts": [{"path": path, "sha256": digest(evidence_bytes(root, path))} for path in SOURCE_PATHS],
        "evidenceIDs": EVIDENCE_IDS, "result": "PASS", "verificationMode": "STATIC_ONLY",
        "nativeCompileRan": False, "hostedDispatchRan": False, "hostedDispatchEnabled": False,
        "acceptanceEnabled": False, "acceptanceCredit": False, "releaseReady": False, "releaseCredit": False,
        "requiresAcceptedS10_6Reconciliation": True}
    return documents


def all_outputs(root: Path) -> dict[str, bytes]:
    outputs = {path: pretty(value) for path, value in schemas().items()}
    outputs.update({path: pretty(value) for path, value in contract_documents(root).items()})
    materialized = {
        path: outputs[path] if path in outputs else evidence_bytes(root, path)
        for path in MANIFEST_INPUT_PATHS
    }
    rows = [{"path": path, "bytes": len(materialized[path]), "sha256": digest(materialized[path])} for path in MANIFEST_INPUT_PATHS]
    tooling = {"schema": "V23P03C06ToolingManifestV1", "schemaVersion": 1, "cardID": CARD,
               "byteNormalization": BYTE_NORMALIZATION, "authority": authority(),
               "pathFence": PATH_FENCE, "pathFenceCount": len(PATH_FENCE), "existingPaths": EXISTING_PATHS,
               "newPaths": NEW_PATHS, "sourcePathCount": len(SOURCE_PATHS), "toolPathCount": len(TOOL_PATHS),
               "artifactCount": len(rows), "pendingArtifactCount": 0, "artifacts": rows,
               "artifactSetDigest": digest(canonical(rows)), "verificationMode": "STATIC_ONLY",
               "nativeCompileRan": False, "hostedDispatchRan": False, "acceptanceEnabled": False,
               "acceptanceCredit": False, "releaseReady": False, "releaseCredit": False,
               "requiresAcceptedS10_6Reconciliation": True}
    outputs[MANIFEST] = pretty(sealed_document(tooling))
    return outputs


def test_methods(root: Path) -> list[str]:
    import re
    return re.findall(r"\bfunc\s+(testV9_16[A-Za-z0-9_]*)\s*\(", (root / SOURCE_PATHS[7]).read_text(encoding="utf-8"))
