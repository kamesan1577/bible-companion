import concurrent.futures,copy,importlib.util,json,tempfile,time,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('jobs',Path(__file__).with_name('codex-jobs.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class JobsTests(unittest.TestCase):
 def setUp(self):self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)/'jobs';m.prepare(self.root,'ACT',['18:7-11','18:12-17'],max_workers=1,max_attempts=2,min_spacing=0)
 def tearDown(self):self.tmp.cleanup()
 def entry(self,job):
  p=m.read(job['packet']);q=p['passage'];return {'id':f"ja-v1:ACT:{q['start']['chapter']}:{q['start']['verse']}-{q['end']['verse']}",'passage':q,'titleJa':'構造検査専用','summaryJa':'これは構造検査専用の固定文です。聖書解説として公開するものではありません。','authorInterpretationJa':'これは原典整合性を保証しない検査用の固定文です。','editorialNoteJa':'これはテスト専用で、実モデルの品質測定ではありません。','sourceUnitIds':[p['sources'][0]['id']],'evidence':[{'sourceUnitId':p['sources'][0]['id'],'quote':p['sources'][0]['originalText'][:30],'primaryRefs':[next(iter(p['primaryText']))]}],'people':[],'editingMethod':'Codex gpt-6-luna source-based Japanese editorial summary; not a literal translation','reviewStatus':'draft-awaiting-independent-source-review; no expert review','spoilerEnd':q['end']}
 def submit(self,j,entry=None,now=None):
  entry=self.entry(j)if entry is None else entry;m.write(j['output'],entry);return m.submit(self.root,j['jobId'],j['lease'],j['output'],now=now)
 def report(self,j,entry,reviewer='different-worker',verdict='pass'):
  r={'jobId':j['jobId'],'draftSha256':m.sha(entry),'reviewer':reviewer,'sourceCompared':True,'primaryCompared':True,'identityCompared':True,'spoilerCompared':True,'interpretationSeparated':True,'verdict':verdict,'notes':'構造テスト用。実際の編集点検の証明ではない。'};p=self.root/'reviews'/(j['jobId']+'.json');m.write(p,r);return p
 def test_quota_and_spawn_limit_pause_without_fallback(self):
  j=m.claim(self.root,'luna');result=m.fail(self.root,j['jobId'],j['lease'],'quota');self.assertTrue(result['paused']);self.assertFalse(result['modelFallback']);self.assertIsNone(m.claim(self.root,'other'));m.pause(self.root,False);self.assertIsNotNone(m.claim(self.root,'retry'))
 def test_atomic_concurrency_bound(self):
  with concurrent.futures.ThreadPoolExecutor(max_workers=4)as pool:claims=list(pool.map(lambda i:m.claim(self.root,str(i)),range(4)))
  self.assertEqual(sum(j is not None for j in claims),1)
 def test_rate_cap_no_attempt_or_dispatch(self):
  db=m.db_open(self.root);db.execute('UPDATE limits SET min_spacing=10,max_workers=2');db.commit();db.close();self.assertIsNotNone(m.claim(self.root,'one',now=100));self.assertIsNone(m.claim(self.root,'two',now=101));self.assertIsNotNone(m.claim(self.root,'two',now=110))
 def test_source_budget_fail_closed(self):
  db=m.db_open(self.root);db.execute('UPDATE limits SET max_chars=1');db.commit();db.close();self.assertIsNone(m.claim(self.root,'worker'));self.assertEqual(m.status(self.root)['jobs'][0]['attempts'],0)
 def test_resume_cache_does_not_rerun_accepted(self):
  j=m.claim(self.root,'author');e=self.entry(j);self.submit(j,e);m.record_review(self.root,j['jobId'],self.report(j,e));m.prepare(self.root,'ACT',['18:7-11','18:12-17'],max_workers=1,max_attempts=2,min_spacing=0);state=m.status(self.root);self.assertEqual(len(state['jobs']),2);nextjob=m.claim(self.root,'second');self.assertNotEqual(j['jobId'],nextjob['jobId'])
 def test_source_and_prompt_versions_change_cache_identity(self):
  before={j['id']for j in m.status(self.root)['jobs']};old=m.PROMPT
  try:m.PROMPT='test-new-prompt';m.prepare(self.root,'ACT',['18:7-11'],max_workers=1,max_attempts=2,min_spacing=0)
  finally:m.PROMPT=old
  after={j['id']for j in m.status(self.root)['jobs']};self.assertEqual(len(after-before),1)
 def test_stale_lease_cannot_overwrite(self):
  a=m.claim(self.root,'old',now=100);b=m.claim(self.root,'new',now=1001);self.assertEqual(a['jobId'],b['jobId']);m.write(a['output'],self.entry(a))
  with self.assertRaises(AssertionError):m.submit(self.root,a['jobId'],a['lease'],a['output'],now=1002)
  self.assertEqual(self.submit(b,now=1002)['state'],'draft')
 def test_malformed_refs_fail_and_only_failed_job_retries(self):
  a=m.claim(self.root,'first');e=self.entry(a);e['evidence'][0]['primaryRefs']=[{'book':'ACT','chapter':18,'verse':7}];self.assertEqual(self.submit(a,e)['state'],'pending');b=m.claim(self.root,'retry');self.assertEqual(a['jobId'],b['jobId']);self.assertEqual(self.submit(b,e)['state'],'blocked');c=m.claim(self.root,'other');self.assertNotEqual(a['jobId'],c['jobId'])
 def test_exact_quote_spoiler_identity_and_density(self):
  j=m.claim(self.root,'worker');p=m.read(j['packet']);e=self.entry(j)
  for field,value in [('quote','not an actual source quote'),('primaryRefs',['ACT:19:1'])]:
   bad=copy.deepcopy(e);bad['evidence'][0][field]=value;self.assertTrue(m.inspect_entry(bad,p))
  bad=copy.deepcopy(e);bad['people']=[{'id':'made-up','nameJa':'同名','roleJa':'役割','identityStatus':'uncertain'}];self.assertIn('person identity',m.inspect_entry(bad,p));bad=copy.deepcopy(e);bad['summaryJa']='短い一文だけです。';self.assertIn('density: summary requires 2-4 sentences',m.inspect_entry(bad,p))
 def test_review_binds_exact_output_and_requires_other_worker(self):
  j=m.claim(self.root,'author');e=self.entry(j);self.submit(j,e)
  with self.assertRaises(AssertionError):m.record_review(self.root,j['jobId'],self.report(j,e,reviewer='author'))
  r=self.report(j,e);v=m.read(r);v['draftSha256']='0'*64;m.write(r,v)
  with self.assertRaises(AssertionError):m.record_review(self.root,j['jobId'],r)
  self.assertEqual(m.record_review(self.root,j['jobId'],self.report(j,e))['state'],'source-reviewed')
 def test_no_incomplete_or_unreviewed_export(self):
  j=m.claim(self.root,'author');self.submit(j)
  with self.assertRaises(AssertionError):m.export(self.root,self.root/'candidate.json')
 def test_input_overlap_and_missing_primary_are_rejected(self):
  with self.assertRaises(AssertionError):m.prepare(Path(self.tmp.name)/'overlap','ACT',['18:7-11','18:7-11'])
  with self.assertRaises(AssertionError):m.prepare(Path(self.tmp.name)/'missing','ACT',['24:5-8'])
if __name__=='__main__':unittest.main()
