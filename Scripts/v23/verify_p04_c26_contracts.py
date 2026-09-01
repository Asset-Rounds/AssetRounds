import argparse,json
import p04_c26_contracts as c
def main():
 p=argparse.ArgumentParser();p.add_argument('--complete',action='store_true');p.add_argument('--json',action='store_true');a=p.parse_args();fails=[]
 try:
  d=c.documents();c.semantics(d[c.CONTRACT]['sourceProjection']['sourceReady'])
  for path,value in d.items():
   if not(c.ROOT/path).is_file()or(c.ROOT/path).read_bytes()!=c.pretty(value):fails.append('drift:'+path)
 except Exception as e:fails.append(str(e))
 out={'cardID':c.CARD,'result':'PASS_STATIC_PROVISIONAL'if not fails else'FAIL_STATIC','failures':fails,'sourceReady':not any(x.get('status')=='SOURCE_MISSING'for x in(c.rows()[0])),'finalHashesSealed':c.FINAL_HASHES_SEALED,'flagsAllFalse':not any(c.FLAGS.values()),'fencePathCount':16,'existingPathCount':2,'newPathCount':14,'counts':c.counts(),'selectors':list(c.SELECTORS)}
 print(json.dumps(out,sort_keys=True,indent=2)if a.json else out['result'])
 raise SystemExit(1 if fails else 0)
if __name__=='__main__':main()
