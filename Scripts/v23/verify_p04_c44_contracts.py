#!/usr/bin/env python3
"""Verify C44 provisional tooling, source seams, and exact path fence."""
from __future__ import annotations
import argparse,json,re,sys
from pathlib import Path
sys.dont_write_bytecode=True;ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(Path(__file__).resolve().parent));import p04_c44_contracts as c
def req(ok,msg,fs):
 if not ok:fs.append(msg)
def tokens(text,label,values,fs):
 for value in values:req(value in text,label+' missing structural token: '+value,fs)
def validate_source(fs):
 existing=[(ROOT/p).read_text(encoding='utf-8') for p in c.EXISTING_PATHS];new=[(ROOT/p).read_text(encoding='utf-8') for p in c.NEW_PRODUCT_PATHS];domain,coordinator,view,tests,fixture,ui=new;contracts,basecoordinator,manual,writer=existing
 tokens(contracts,'existing parts contracts',('StockBalanceProjectionV1','StockReturnAgainstUseReceiptV1'),fs)
 tokens(domain,'C44 durable contract',('LocalStockFeaturePolicyV1','LOCAL_PART_CATALOG_V1','Use','Count','low','CSV'),fs)
 tokens(coordinator,'C44 coordinator',('preview','commit','Use','Return','MutationID'),fs)
 tokens(manual,'manual work boundary',('material','stock'),fs)
 tokens(writer,'writer boundary',('PartsStock','return','overflow'),fs)
 tokens(view,'C44 view',('LocalStockFeaturePolicyV1','Count','Adjust','Transfer','Use','Return','Archive','CSV'),fs)
 tokens(tests,'C44 tests',('V23P04C44G01','V23P04C44A01','V23P04C44H01','V23P04C44I01','CSV'),fs)
 tokens(ui,'C44 UI adoption boundary',('throw XCTSkip(','post-S10'),fs)
 try:fixture_json=json.loads(fixture);req(isinstance(fixture_json,dict),'fixture must be JSON object',fs)
 except Exception as e:fs.append('fixture JSON: '+str(e))
def main():
 p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();fs=[]
 try:expected=c.documents()
 except Exception as e:expected={};fs.append('authority:'+str(e))
 docs={}
 for path in (c.SCHEMA,c.CONTRACT,c.EVIDENCE,c.BRAND,c.MANIFEST):
  try:docs[path]=c.read_json(path)
  except Exception as e:fs.append('artifact:'+str(e))
 for path,value in expected.items():req(docs.get(path)==value,'deterministic artifact differs: '+path,fs)
 rows,ready=c.rows()
 if a.complete and not ready:fs.append('complete:missing C44 source paths')
 if ready:validate_source(fs)
 changed=set(c.git('diff','--name-only',c.BASE,'HEAD').splitlines())|set(c.git('diff','--name-only','HEAD').splitlines())|set(c.git('diff','--cached','--name-only').splitlines())|set(c.git('ls-files','--others','--exclude-standard').splitlines());changed.discard('');unowned=changed-set(c.PATH_FENCE)
 if unowned:fs.append('unowned changed paths: '+','.join(sorted(unowned)))
 counts={'changedPathCount':len(changed&set(c.PATH_FENCE)),'unownedChangedPathCount':len(unowned),'missingPathCount':sum(not(ROOT/x).is_file() for x in c.PATH_FENCE),'fencePathCount':18,'existingPathCount':4,'newPathCount':14,'productTestUIFixturePathCount':6,'toolingPathCount':8,'s10ReservationOverlapCount':0}
 result={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL' if not fs else 'FAIL_STATIC','sourceReady':ready,'finalHashesSealed':False,'flagsAllFalse':all(x is False for x in c.FLAGS.values()),'failures':fs,'counts':counts,'selectors':list(c.SELECTORS),'authoritySequence':c.SEQUENCE,'sourceRows':rows};print(json.dumps(result,sort_keys=True,indent=2 if a.json else None));return 0 if not fs else 1
if __name__=='__main__':raise SystemExit(main())
