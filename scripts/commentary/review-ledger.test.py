import copy,hashlib,json,runpy,unittest
from pathlib import Path
verify=runpy.run_path(str(Path(__file__).with_name('review-ledger.py')))['verify']
class ReviewLedgerTests(unittest.TestCase):
 def setUp(self):
  e={'id':'sample','summaryJa':'確認した説明。','sourceUnitIds':['jfb-ccel1871-context:source']};self.edits={'entries':[e],'independentReviewedEntryIds':['sample']};self.ledger={'entries':[{'id':'sample','canonicalEntrySha256':hashlib.sha256(json.dumps(e,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'verdict':'pass','checks':dict.fromkeys(['primaryMeaning','sourceAttribution','identity','spoiler','density'],True),'reasonJa':'原典の具体的内容を照合。'}]}
 def test_current_review_passes(self):self.assertEqual(verify(self.edits,self.ledger),1)
 def test_changed_explanation_requires_new_review(self):
  self.edits['entries'][0]['summaryJa']='改訂。'
  with self.assertRaises(ValueError):verify(self.edits,self.ledger)
 def test_missing_or_duplicate_review_fails(self):
  for rows in [[],self.ledger['entries']*2]:
   with self.assertRaises(ValueError):verify(self.edits,{'entries':rows})
 def test_incomplete_semantic_review_fails(self):
  self.ledger['entries'][0]['checks']['spoiler']=False
  with self.assertRaises(ValueError):verify(self.edits,self.ledger)
 def test_unaccepted_id_fails(self):
  self.edits['independentReviewedEntryIds']=[]
  with self.assertRaises(ValueError):verify(self.edits,self.ledger)
if __name__=='__main__':unittest.main()
