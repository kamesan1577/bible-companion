"""Fail closed when final CCEL edits no longer match their native review ledger."""
import hashlib,json

def verify(edits, ledger):
 entries={e['id']:e for e in edits['entries'] if any(i.startswith('jfb-ccel1871-context:') for i in e['sourceUnitIds'])}
 records=ledger['entries']; byid={r['id']:r for r in records}
 if len(byid)!=len(records) or set(entries)!=set(byid):raise ValueError('Review ledger must cover every final CCEL entry exactly once')
 reviewed=set(edits.get('independentReviewedEntryIds',[]))
 checks={'primaryMeaning','sourceAttribution','identity','spoiler','density'}
 for key,entry in entries.items():
  r=byid[key];digest=hashlib.sha256(json.dumps(entry,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
  if r['canonicalEntrySha256']!=digest or r['verdict']!='pass' or key not in reviewed:raise ValueError('Missing or stale accepted review: '+key)
  if not checks<=r['checks'].keys() or not all(r['checks'][k] is True for k in checks) or not r.get('reasonJa'):raise ValueError('Incomplete semantic review: '+key)
 return len(entries)
