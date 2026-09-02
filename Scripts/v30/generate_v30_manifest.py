#!/usr/bin/env python3
"""Generate/verify the exhaustive V30 R2 package manifest without self-hash."""
from __future__ import annotations
import argparse, hashlib, json, sys
from pathlib import Path
from typing import Any

P=Path(__file__).resolve().parent
OUT=P/"V30_PACKAGE_MANIFEST.json"
AUTH=P/"V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json"
HUMAN_FILES={"EXPANSION_V30_FOUNDATION_PLAN.md","EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md","EXPANSION_V30_HANDOFF.md","NEXT_CODEX_SESSION_PROMPT.md"}
STRUCTURAL_FILES={"V30_CARD_REGISTER.json","V30_DIRECT_DEPENDENCY_GRAPH.json","V30_LOCALE_REGISTRY.json","V30_V24_DISPOSITION_PROJECTION.json"}
FILES={
 "EXPANSION_V30_FOUNDATION_PLAN.md","EXPANSION_V30_ARCHITECTURE_BLUEPRINT.md","EXPANSION_V30_HANDOFF.md","NEXT_CODEX_SESSION_PROMPT.md",
 "generate_v30_machine_artifacts.py","generate_v30_path_fences.py","generate_v30_authority.py","generate_v30_bootstrap_payloads.py","generate_v30_manifest.py","validate_v30_package.py",
 "V30_CARD_REGISTER.json","V30_DIRECT_DEPENDENCY_GRAPH.json","V30_LOCALE_REGISTRY.json","V30_V24_DISPOSITION_PROJECTION.json","V30_PRE_S10_PATH_FENCES.json","V30_PRE_S10_PROVISIONAL_IMPLEMENTATION_AUTHORITY.json",
 "V30_CARD_001_CONTEXT.json","V30_CARD_001_FENCE.json","V30_CARD_001_CURRENT_TASK.md","V30_CARD_001_CI_SELECTION.json","V30_EXECUTION_HANDOFF_GENESIS.md","V30_PROVISIONAL_LEDGER_GENESIS.json","V30_PROVISIONAL_LEDGER_PROJECTION.json"}
class Hold(RuntimeError): pass
def req(ok:bool,why:str)->None:
 if not ok: raise Hold(why)
def sha(raw:bytes)->str:return hashlib.sha256(raw).hexdigest()
def canon(x:Any)->bytes:return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(",",":")).encode()
def build()->dict[str,Any]:
 actual={x.name for x in P.iterdir() if x.is_file()}
 req(actual in (FILES,FILES|{OUT.name}),f"unexpected or missing package files: {sorted(actual ^ FILES)}")
 authority=json.loads(AUTH.read_text(encoding="utf-8")); ident=authority.get("authority",{})
 aid=ident.get("id") if isinstance(ident,dict) else None; adigest=authority.get("authorityContentDigest")
 req(aid=="ASSETROUNDS-V30-PRE-S10-20260902-R2" and isinstance(adigest,str) and len(adigest)==64,"authority identity")
 mapping=authority.get("sourceToInstallMap")
 req(isinstance(mapping,list) and len(mapping)==24,"authority source map")
 req({x.get("source") for x in mapping if isinstance(x,dict)}==FILES|{OUT.name},"authority source map coverage")
 records=[{"path":n,"sha256":sha((P/n).read_bytes()),"bytes":(P/n).stat().st_size} for n in sorted(FILES)]
 return {"schema":"V30PackageManifestV1","schemaVersion":1,"packageRevision":"R2","digestScheme":"V30CanonicalJSONSHA256LFV1","authorityID":aid,"authorityContentDigest":adigest,"repository":{"name":"AssetRounds","remoteURL":"https://github.com/Asset-Rounds/AssetRounds.git"},"frozenV23":{"head":"acbfb68355f903fe98638b6ef22e4814e7b48328","tree":"47e17fae6b73dccd5029ccf4ac7cca659196f225"},"frozenCoordination":{"head":"51ef2b3d970a25b4c83df8c8238609316e37034e","tree":"060c83c3d1489fc011b1c921f6c85bec2b074478","sequence":626},"cardCount":55,"edgeCount":107,"initialLocaleCount":6,"v24DispositionCount":97,"sourceToInstallMap":mapping,"files":records,"packageDigest":sha(canon(records)+b"\n"),"humanPackageDigest":sha(canon([record for record in records if record["path"] in HUMAN_FILES])+b"\n"),"structuralProjectionDigest":sha(canon([record for record in records if record["path"] in STRUCTURAL_FILES])+b"\n")}
def main()->int:
 ap=argparse.ArgumentParser();g=ap.add_mutually_exclusive_group(required=True);g.add_argument("--apply",action="store_true");g.add_argument("--check",action="store_true");a=ap.parse_args();value=build()
 if a.apply:
  OUT.write_bytes(json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True).encode()+b"\n"); print(json.dumps({"result":"APPLIED","packageDigest":value["packageDigest"],"fileCount":len(value["files"])},sort_keys=True))
 else:
  req(OUT.is_file() and json.loads(OUT.read_text(encoding="utf-8"))==value,"manifest differs from deterministic projection");print(json.dumps({"result":"PASS","packageDigest":value["packageDigest"],"fileCount":len(value["files"])},sort_keys=True))
 return 0
if __name__=="__main__":
 try:raise SystemExit(main())
 except (Hold,ValueError) as e:print(json.dumps({"result":"HOLD","reason":str(e)},sort_keys=True),file=sys.stderr);raise SystemExit(2)
