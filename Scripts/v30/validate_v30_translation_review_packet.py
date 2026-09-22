#!/usr/bin/env python3
"""Read-only V30 termbase/review-packet integrity checks. No acceptance or transfer.

Source manifests must be prepared and frozen by the source custodian. Matching
untrusted files to each other cannot establish authorship, privacy or linguistic
quality. Receipts remain evidence supplied by real authorized reviewers.
"""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / "docs/design/v30/translation"
TERM = DIRECTORY / "V30TermbaseV1.json"
WORKFLOW = DIRECTORY / "V30SecureLinguisticReviewWorkflowV1.json"
SCHEMA = DIRECTORY / "V30TranslationReviewPacketSchemaV1.json"
LOCALES = ["en", "es", "zh-Hans", "zh-Hant", "vi", "ko"]
FOUNDATION_SOURCE = "0d1761199d58166909da02378f70f369dbade822"
SOURCE_PATHS = {
    "docs/design/v30/EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md",
    "docs/design/v30/research/V30KeywordEvidenceBindingV1.json",
    "FieldEvidenceApp/Domain/Globalization/LocalizedSyncStateContractsV1.swift",
    "FieldEvidenceApp/Features/Globalization/CriticalSurfaceLocalizationRegistryV1.swift",
    "FieldEvidenceApp/Domain/Localization/LocalizationContractsV1.swift",
}
PLURAL_MINIMUM = {locale: ({"one", "other"} if locale in {"en", "es"} else {"other"}) for locale in LOCALES}
PLURAL_CATEGORIES = dict(PLURAL_MINIMUM, es={"one", "many", "other"})


class Invalid(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise Invalid(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def digest(value):
    return sha(canonical(value))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate JSON key")
        result[key] = value
    return result


def read(path):
    require(path.stat().st_size <= 32 * 1024 * 1024, "JSON exceeds packet size limit")
    return json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=unique_object,
                      parse_constant=lambda _: (_ for _ in ()).throw(Invalid("nonfinite JSON")))


def schema_check(value, spec, context="$", schema_root=None):
    """Closed, dependency-free evaluation of the vocabulary used in our schema."""
    if "anyOf" in spec:
        for choice in spec["anyOf"]:
            try:
                schema_check(value, choice, context)
                return
            except Invalid:
                pass
        raise Invalid(context + ": no allowed shape")
    if "const" in spec:
        require(type(value) is type(spec["const"]) and value == spec["const"], context + ": constant mismatch")
    if "enum" in spec:
        require(any(type(value) is type(x) and value == x for x in spec["enum"]), context + ": unknown value")
    kind = spec.get("type")
    types = {"object": dict, "array": list, "string": str, "integer": int, "boolean": bool, "null": type(None)}
    if kind:
        require(type(value) is types[kind], context + ": wrong type")
    if isinstance(value, dict):
        require(set(spec.get("required", [])) <= value.keys(), context + ": missing fields")
        require(len(value) >= spec.get("minProperties", 0), context + ": empty map")
        props = spec.get("properties", {})
        extra = spec.get("additionalProperties", True)
        for key, item in value.items():
            if "propertyNames" in spec:
                schema_check(key, spec["propertyNames"], context + ": key")
            if key in props:
                schema_check(item, props[key], context + "." + key)
            elif extra is False:
                raise Invalid(context + ": unknown field")
            elif isinstance(extra, dict):
                schema_check(item, extra, context + "." + key)
    if isinstance(value, list):
        require(len(value) >= spec.get("minItems", 0), context + ": missing entries")
        if spec.get("uniqueItems"):
            require(len({canonical(x) for x in value}) == len(value), context + ": duplicate entries")
        for item in value:
            schema_check(item, spec.get("items", {}), context + "[]")
    if isinstance(value, str):
        require(len(value.strip()) >= spec.get("minLength", 0), context + ": empty text")
        if "pattern" in spec:
            require(re.search(spec["pattern"], value) is not None, context + ": invalid syntax")
    if type(value) is int and "minimum" in spec:
        require(value >= spec["minimum"], context + ": below minimum")


def keyed(values, key):
    result = {row[key]: row for row in values}
    require(len(result) == len(values), "duplicate " + key)
    return result


def safe_file(root, relative):
    """No absolute, Windows alternate-stream, traversal, symlink or junction escape."""
    path = PurePosixPath(relative)
    require(relative and "\\" not in relative and ":" not in relative
            and not path.is_absolute() and all(p not in {"", ".", ".."} for p in relative.split("/")),
            "unsafe artifact path")
    resolved_root = root.resolve(strict=True)
    target = root / relative
    require(target.resolve(strict=True).is_relative_to(resolved_root), "artifact escapes root")
    require(target.is_file(), "missing artifact file")
    return target


def bound_source(binding):
    # Git blob bytes avoid checkout line-ending differences and retain the
    # historical source when a later authorized card changes that file.
    require(binding["revision"] == FOUNDATION_SOURCE, "source binding revision")
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", binding["path"])
            and ".." not in binding["path"].split("/"), "source binding path")
    data = subprocess.check_output(["git", "-C", str(ROOT), "show",
                                    binding["revision"] + ":" + binding["path"]], stderr=subprocess.DEVNULL)
    require(sha(data) == binding["sha256"], "source binding bytes mismatch")


def foundation():
    term, workflow, schema = read(TERM), read(WORKFLOW), read(SCHEMA)
    require(term["kind"] == "V30TermbaseV1" and term["schemaVersion"] == 1, "termbase schema")
    require(term["targetLocales"] == LOCALES and term["shippingTranslationApproval"] is False, "termbase credit")
    concepts = keyed(term["entries"], "conceptID")
    for cid, entry in concepts.items():
        require(re.fullmatch(r"(?:core|sign|state|action|product)\.[a-z_]+", cid), "concept ID")
        require(entry["namespace"] == cid.split(".")[0] and entry["sourceLocale"] == "en", "concept namespace")
        require(entry["preferredTerm"] and entry["context"] and entry["forbiddenAlternatives"], "incomplete concept")
        require(entry["localeTerms"] == {} and entry["reviewStatus"] == "SOURCE_SEMANTICS_FROZEN_NOT_LINGUISTIC_ACCEPTANCE", "unsupported linguistic credit")
    required = {"sign.sign", "core.site", "core.asset", "sign.inspection", "core.round", "core.issue", "core.work",
                "core.recheck", "core.evidence", "core.report", "core.history", "core.backup", "core.restore",
                "core.subscription", "core.status", "core.severity", "core.confidence"}
    require(required <= concepts.keys(), "incomplete required terminology")
    dnt = keyed(term["doNotTranslate"], "id")
    require(dnt["dnt.erase"]["value"] == "ERASE" and dnt["dnt.brand"]["value"] == "AssetRounds", "authority token")
    require(set(keyed(term["sourceBindings"], "path")) == SOURCE_PATHS, "source binding path set")
    for binding in term["sourceBindings"]:
        bound_source(binding)
    research = read(ROOT / "docs/design/v30/research/V30KeywordEvidenceBindingV1.json")
    require([x["researchLabel"] for x in term["futureNamespaces"]] == research["proposedVerticalSequence"]["orderedLabels"][1:], "future research sequence")
    require(all(x["productActivation"] is False and x["terms"] == [] and x["status"] == "RESERVED_RESEARCH_ONLY" for x in term["futureNamespaces"]), "future scope activation")
    require(workflow["shippingAcceptance"] is False and workflow["networkTranslationRequired"] is False
            and workflow["export"]["automaticUpload"] is False, "workflow credit or transfer")
    require(workflow["correction"]["terminalOutcomes"] == ["ACCEPTED_NO_CORRECTION", "CORRECTION_REQUIRED"], "review outcomes")
    binding = workflow["screenshotContract"]["source"]
    require(binding["path"] == "docs/design/v30/verification/V30P02C06ProvisionalScreenshotHarnessContractV1.json", "screenshot binding path")
    bound_source(binding)
    require(schema["properties"]["locale"]["enum"] == LOCALES, "packet cohort")
    return term, workflow, schema


TOKEN = re.compile(r"%(?:(?P<index>[1-9][0-9]*)\$)?(?P<type>@|lld|llu|ld|lu|d|u|f)|%#@(?P<name>[A-Za-z_][A-Za-z0-9_]*)@|%%")


def placeholders(text):
    """Typed/count-preserving printf references; positional reordering is allowed.

    Unsupported format grammar fails closed for explicit source-custodian review.
    Literal percent signs must be escaped as %% in packet format strings.
    """
    result = collections.Counter()
    offset, sequential = 0, 0
    styles = set()
    for match in TOKEN.finditer(text):
        require("%" not in text[offset:match.start()], "unsupported placeholder")
        offset = match.end()
        if match.group() == "%%":
            continue
        if match["name"]:
            result[("named", match["name"])] += 1
        else:
            styles.add("position" if match["index"] else "sequence")
            sequential += 1
            result[(int(match["index"] or sequential), match["type"])] += 1
    require("%" not in text[offset:] and len(styles) <= 1, "unsupported/mixed placeholders")
    return result


def variant_families(forms, locale):
    families = {}
    for selector, text in forms.items():
        family = re.sub(r"plural\.(zero|one|two|few|many|other)$", "plural", selector)
        families.setdefault(family, {})[selector] = text
    for family, variants in families.items():
        if family.endswith("plural"):
            categories = {selector.rsplit(".", 1)[1] for selector in variants}
            require(PLURAL_MINIMUM[locale] <= categories <= PLURAL_CATEGORIES[locale], "locale plural branches incomplete/unsupported")
    return families


def validate_packet(packet, source, artifact_root, term, workflow, schema, predecessor=None):
    schema_check(packet, schema)
    schema_check(source, schema["x-sourceManifest"])
    require(packet["sourcePayloadDigest"] == digest(source), "source manifest digest")
    require(packet["sourceRevision"] == source["sourceRevision"] and packet["sourceTree"] == source["sourceTree"], "source revision/tree mismatch")
    require(packet["termbaseDigest"] == sha(TERM.read_bytes()) and packet["workflowDigest"] == sha(WORKFLOW.read_bytes()), "foundation digest mismatch")
    require(packet["supplyChain"]["deliverableDigest"] == digest(packet["entries"]), "deliverable digest")
    require((packet["revision"] == 1) == (packet["supersedes"] is None), "revision/supersedes mismatch")
    if packet["revision"] == 1:
        require(packet["correctionOf"] is None and predecessor is None, "initial packet cannot correct prior evidence")
    else:
        correction = packet["correctionOf"]
        require(correction is not None and predecessor is not None, "correction requires actual predecessor packet")
        schema_check(predecessor, schema)
        require(packet["supersedes"] == correction["packetDigest"] == digest(predecessor), "correction predecessor digest mismatch")
        require(packet["revision"] == predecessor["revision"] + 1 and packet["packetID"] == predecessor["packetID"]
                and packet["locale"] == predecessor["locale"], "correction stream/revision mismatch")
        prior_receipt, prior_tuple = predecessor["receipt"], predecessor["candidateTuple"]
        require(predecessor["status"] == "REVIEWED" and prior_receipt is not None and prior_tuple is not None
                and prior_receipt["outcome"] == "CORRECTION_REQUIRED", "predecessor did not request correction")
        require(correction["receiptID"] == prior_receipt["id"] and correction["candidateTupleDigest"]
                == prior_receipt["candidateTupleDigest"] == digest(prior_tuple), "correction receipt/tuple mismatch")
    original, translated = keyed(source["entries"], "key"), keyed(packet["entries"], "key")
    require(original.keys() == translated.keys(), "required key set mismatch")
    concepts = keyed(term["entries"], "conceptID")
    dnt = keyed(term["doNotTranslate"], "id")
    for key, row in translated.items():
        require({k: v for k, v in row.items() if k != "targetForms"} == original[key], "source entry changed")
        require(set(row["conceptIDs"]) <= concepts.keys() and set(row["doNotTranslateIDs"]) <= dnt.keys(), "unknown concept/disposition")
        for rule_id, rule in dnt.items():
            if any(rule["value"] in value for value in row["sourceForms"].values()):
                require(rule_id in row["doNotTranslateIDs"], "source token lacks explicit disposition")
        source_families = variant_families(row["sourceForms"], "en")
        target_families = variant_families(row["targetForms"], packet["locale"])
        require(source_families.keys() == target_families.keys(), "variation family missing/added")
        for family, targets in target_families.items():
            defaults = source_families[family]
            fallback = defaults.get(family + ".other")
            for selector, target_text in targets.items():
                source_text = defaults.get(selector, fallback)
                require(source_text is not None and placeholders(target_text) == placeholders(source_text), "placeholder type/count mismatch")
                for rule_id in row["doNotTranslateIDs"]:
                    token = dnt[rule_id]["value"]
                    require(source_text.count(token) == target_text.count(token), "do-not-translate token changed")
        # Every plural branch has a compatible placeholder signature, including
        # source-only English categories not used by the destination language.
        for family, forms in source_families.items():
            if family.endswith("plural"):
                require(all(placeholders(v) == placeholders(forms[family + ".other"]) for v in forms.values()), "inconsistent source plural placeholders")
        if packet["locale"] == "en":
            require(row["targetForms"] == row["sourceForms"], "English source change needs source owner")
    artifacts = keyed(packet["artifacts"], "id")
    require(len({a["path"].casefold() for a in artifacts.values()}) == len(artifacts), "duplicate artifact path")
    for artifact in artifacts.values():
        path = safe_file(artifact_root, artifact["path"])
        require(path.stat().st_size <= 64 * 1024 * 1024, "artifact exceeds size limit")
        require(sha(path.read_bytes()) == artifact["sha256"], "artifact bytes changed")
        require(artifact["context"]["language"] == packet["locale"], "artifact language mismatch")
    candidate, receipt = packet["candidateTuple"], packet["receipt"]
    if packet["status"] == "DRAFT_NONSHIPPING":
        require(candidate is None and receipt is None, "draft cannot carry review acceptance")
    else:
        require(not packet["machineAssisted"] and candidate is not None and artifacts, "review requires human candidate artifacts")
        require(candidate["candidateHead"] == packet["sourceRevision"] and candidate["candidateTree"] == packet["sourceTree"], "candidate source mismatch")
        require(candidate["termbaseDigest"] == packet["termbaseDigest"] and candidate["requiredKeySetDigest"] == digest(sorted(original)), "candidate termbase/key set mismatch")
        require(candidate["renderedReviewArtifactDigests"] == {k: a["sha256"] for k, a in artifacts.items()}, "candidate artifact mismatch")
        require(packet["supplyChain"]["translatorReference"] is not None and packet["supplyChain"]["reviewerReference"] is not None
                and packet["supplyChain"]["translatorReference"] != packet["supplyChain"]["reviewerReference"], "independent role references required")
        if packet["status"] == "READY_FOR_REVIEW":
            require(receipt is None, "ready packet cannot carry terminal receipt")
        else:
            require(receipt is not None and receipt["candidateTupleDigest"] == digest(candidate), "receipt tuple mismatch")
            require(set(receipt["artifactDigests"]) == {a["sha256"] for a in artifacts.values()}, "receipt artifact mismatch")
            roles = collections.defaultdict(list)
            for role in receipt["roleReceipts"]:
                roles[role["role"]].append(role)
            require(len({r["receiptID"] for r in receipt["roleReceipts"]}) == len(receipt["roleReceipts"]), "duplicate role receipt")
            require(set(receipt["affectedKeys"]) <= original.keys(), "unknown correction key")
            if receipt["outcome"] == "ACCEPTED_NO_CORRECTION":
                require(not receipt["affectedKeys"], "accepted receipt requests correction")
                required = {"independentReviewer"} | ({"translator", "bilingualPractitioner"} if packet["locale"] != "en" else set())
                require(required <= roles.keys(), "missing professional/independent/bilingual review")
                translator = packet["supplyChain"]["translatorReference"]
                reviewer = packet["supplyChain"]["reviewerReference"]
                require(any(r["participantID"] == reviewer for r in roles["independentReviewer"]), "reviewer reference mismatch")
                if packet["locale"] != "en":
                    require(any(r["participantID"] == translator for r in roles["translator"]), "translator reference mismatch")
                require(not ({r["participantID"] for r in roles["translator"]} & {r["participantID"] for r in roles["independentReviewer"]}), "reviewer is not independent")
            else:
                require(receipt["affectedKeys"], "correction receipt must identify affected keys")
    return {"result": "PASS_STRUCTURAL_INTEGRITY_ONLY", "keys": len(original), "artifacts": len(artifacts),
            "linguisticAcceptance": False, "nativeCredit": False, "finalCredit": False}


def self_test(term, workflow, schema):
    """Synthetic, temporary mutation tests; they never create real review evidence."""
    source_row = dict(key="test.status", conceptIDs=["core.status"], comment="Synthetic test, no customer data.",
                      sourceForms={"default": "%1$@ has %2$lld records. ERASE"}, doNotTranslateIDs=["dnt.erase"])
    source = dict(kind="V30TranslationSourceManifestV1", schemaVersion=1, sourceRevision="a" * 40,
                  sourceTree="b" * 40, entries=[source_row])
    packet = dict(kind="V30TranslationReviewPacketV1", schemaVersion=1, packetID="synthetic-only", revision=1,
                  supersedes=None, locale="es", status="DRAFT_NONSHIPPING", machineAssisted=True,
                  sourceRevision=source["sourceRevision"], sourceTree=source["sourceTree"], sourcePayloadDigest=digest(source),
                  termbaseDigest=sha(TERM.read_bytes()), workflowDigest=sha(WORKFLOW.read_bytes()),
                  entries=[dict(source_row, targetForms={"default": "%2$lld | %1$@ ERASE"})], artifacts=[],
                  candidateTuple=None, receipt=None, correctionOf=None,
                  supplyChain=dict(syntheticOnly=True, customerDataIncluded=False, custodianID="synthetic-custodian",
                                   attestation="INSPECTED_TEXT_AND_IMAGES_SYNTHETIC_ONLY", licenseUsageTerms="Synthetic tests only, no external transfer.",
                                   deliverableDigest="0" * 64, translatorReference=None, reviewerReference=None))
    packet["supplyChain"]["deliverableDigest"] = digest(packet["entries"])
    failures = 0
    with tempfile.TemporaryDirectory(prefix="v30-review-contract-") as temporary:
        root = Path(temporary)
        validate_packet(packet, source, root, term, workflow, schema)

        def reject(change, base=packet, manifest=source, rehash=True, predecessor=None):
            nonlocal failures
            value = copy.deepcopy(base)
            change(value)
            if rehash:
                value["supplyChain"]["deliverableDigest"] = digest(value["entries"])
            try:
                validate_packet(value, manifest, root, term, workflow, schema, predecessor)
            except (Invalid, OSError):
                failures += 1
                return
            raise Invalid("negative self-test unexpectedly passed")

        for field, value in [("unknown", True), ("locale", "fr"), ("schemaVersion", True), ("sourceTree", "c" * 40),
                             ("sourcePayloadDigest", "0" * 64), ("termbaseDigest", "0" * 64), ("workflowDigest", "0" * 64),
                             ("revision", 2), ("status", "READY_FOR_REVIEW"), ("entries", [])]:
            reject(lambda p, k=field, v=value: p.update({k: v}))
        reject(lambda p: p["entries"].append(copy.deepcopy(p["entries"][0])))
        for value in ["%1$@", "%1$@ %2$d ERASE", "%2$lld %1$@ borrar", "%2$lld %@ ERASE", "%2$lld %1$@ %1$@ ERASE", "%s ERASE"]:
            reject(lambda p, v=value: p["entries"][0].update(targetForms={"default": v}))
        reject(lambda p: p["entries"][0].update(conceptIDs=["future.unshipped"]))
        reject(lambda p: p["entries"][0].update(sourceForms={"default": "different source"}))
        reject(lambda p: p["entries"][0].update(targetForms={"device.ipad": "%2$lld %1$@ ERASE"}))
        reject(lambda p: p["supplyChain"].update(customerDataIncluded=True))
        reject(lambda p: p["supplyChain"].update(deliverableDigest="0" * 64), rehash=False)
        plural_source = copy.deepcopy(source)
        plural_source["entries"][0]["sourceForms"] = {"plural.one": "%lld record ERASE", "plural.other": "%lld records ERASE"}
        plural = copy.deepcopy(packet)
        plural["locale"] = "zh-Hans"
        plural["sourcePayloadDigest"] = digest(plural_source)
        plural["entries"] = [dict(plural_source["entries"][0], targetForms={"plural.other": "%lld ERASE"})]
        plural["supplyChain"]["deliverableDigest"] = digest(plural["entries"])
        validate_packet(plural, plural_source, root, term, workflow, schema)
        reject(lambda p: p["entries"][0].update(targetForms={"plural.one": "%lld ERASE"}), plural, plural_source)
        reject(lambda p: p.update(locale="es"), plural, plural_source)
        # These are explicitly synthetic file bytes, not screenshot/render evidence.
        (root / "fixture.bin").write_bytes(b"SYNTHETIC CONTRACT TEST ONLY")
        reviewed = copy.deepcopy(packet)
        reviewed.update(status="REVIEWED", machineAssisted=False)
        reviewed["artifacts"] = [dict(id="synthetic-render", path="fixture.bin", sha256=sha((root / "fixture.bin").read_bytes()), kind="screenshot", synthetic=True,
                                     context=dict(workflow="synthetic", state="synthetic", language="es", device="synthetic", os="synthetic", dynamicType="synthetic", appearance="light", contrast="normal", keyboard="hidden"))]
        candidate = dict(candidateHead=source["sourceRevision"], candidateTree=source["sourceTree"], bundledCatalogDigest="c" * 64,
                         perLocaleCatalogReleaseDigests={loc: "d" * 64 for loc in LOCALES}, requiredKeySetDigest=digest([source_row["key"]]),
                         termbaseDigest=reviewed["termbaseDigest"], renderedReviewArtifactDigests={"synthetic-render": reviewed["artifacts"][0]["sha256"]})
        reviewed["candidateTuple"] = candidate
        reviewed["supplyChain"].update(translatorReference="synthetic-translator", reviewerReference="synthetic-reviewer")
        reviewed["receipt"] = dict(id="synthetic-receipt", outcome="ACCEPTED_NO_CORRECTION", candidateTupleDigest=digest(candidate),
                                   artifactDigests=list(candidate["renderedReviewArtifactDigests"].values()), affectedKeys=[], notes="Synthetic negative/positive tests only.",
                                   roleReceipts=[dict(role=r, participantID=p, qualification="SYNTHETIC ONLY", receiptID="synthetic-" + r)
                                                 for r, p in [("translator", "synthetic-translator"), ("independentReviewer", "synthetic-reviewer"), ("bilingualPractitioner", "synthetic-practitioner")]])
        validate_packet(reviewed, source, root, term, workflow, schema)
        reject(lambda p: p.update(machineAssisted=True), reviewed)
        reject(lambda p: p["candidateTuple"].update(requiredKeySetDigest="0" * 64), reviewed)
        reject(lambda p: p["receipt"].update(candidateTupleDigest="0" * 64), reviewed)
        reject(lambda p: p["receipt"].update(affectedKeys=[source_row["key"]]), reviewed)
        reject(lambda p: p["receipt"].update(roleReceipts=p["receipt"]["roleReceipts"][:2]), reviewed)
        reject(lambda p: p["supplyChain"].update(reviewerReference="synthetic-translator"), reviewed)
        reject(lambda p: p["artifacts"][0].update(sha256="0" * 64), reviewed)
        for path in ["../fixture.bin", "C:/fixture.bin", "folder/../fixture.bin", "/fixture.bin"]:
            reject(lambda p, v=path: p["artifacts"][0].update(path=v), reviewed)
        correction = copy.deepcopy(reviewed)
        correction["receipt"].update(outcome="CORRECTION_REQUIRED", affectedKeys=[source_row["key"]])
        validate_packet(correction, source, root, term, workflow, schema)
        reject(lambda p: p["receipt"].update(affectedKeys=[]), correction)
        successor = copy.deepcopy(packet)
        successor.update(revision=2, supersedes=digest(correction), correctionOf=dict(packetDigest=digest(correction),
                         receiptID=correction["receipt"]["id"], candidateTupleDigest=digest(correction["candidateTuple"])))
        validate_packet(successor, source, root, term, workflow, schema, correction)
        reject(lambda p: p.update(correctionOf=None), successor, predecessor=correction)
        reject(lambda p: p.update(supersedes="0" * 64), successor, predecessor=correction)
        reject(lambda p: p["correctionOf"].update(receiptID="unrelated"), successor, predecessor=correction)
        reject(lambda p: p["correctionOf"].update(candidateTupleDigest="0" * 64), successor, predecessor=correction)
        reject(lambda p: p.update(revision=3), successor, predecessor=correction)
        reject(lambda p: None, successor)
        reject(lambda p: p.update(correctionOf=successor["correctionOf"]))
        wrong_source = copy.deepcopy(term["sourceBindings"][0])
        wrong_source["revision"] = "c91f1a1cf9b82c133a6b66be18a856d9dd4cd328"
        try:
            bound_source(wrong_source)
        except Invalid:
            failures += 1
        else:
            raise Invalid("different historical source revision accepted")
        try:
            json.loads('{"key":1,"key":2}', object_pairs_hook=unique_object)
        except Invalid:
            failures += 1
        else:
            raise Invalid("duplicate JSON accepted")
    return {"positiveCases": 5, "negativeCases": failures, "syntheticOnly": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packet", type=Path)
    parser.add_argument("--source", type=Path)
    parser.add_argument("--artifact-root", type=Path)
    parser.add_argument("--predecessor", type=Path, help="Actual superseded packet, required for every correction revision")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        term, workflow, schema = foundation()
        result = dict(result="PASS_FOUNDATION_STATIC", concepts=len(term["entries"]),
                      linguisticAcceptance=False, nativeCredit=False, finalCredit=False)
        if args.packet:
            require(args.source is not None and args.artifact_root is not None, "packet requires frozen source and artifact root")
            result = validate_packet(read(args.packet), read(args.source), args.artifact_root, term, workflow, schema,
                                     read(args.predecessor) if args.predecessor else None)
        else:
            require(args.source is None and args.artifact_root is None and args.predecessor is None, "source/artifact root/predecessor requires packet")
        if args.self_test:
            result["selfTest"] = self_test(term, workflow, schema)
        print(json.dumps(result, sort_keys=True))
        return 0
    except (Invalid, OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        # Only diagnostics, never include imported customer/translator text.
        print(json.dumps({"result": "FAIL", "reason": str(error), "finalCredit": False}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
