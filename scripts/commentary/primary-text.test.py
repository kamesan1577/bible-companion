import copy,json,runpy,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];m=runpy.run_path(str(ROOT/'scripts/commentary/primary-text.py'));sha=m['sha'];resolve=m['resolve']
class AlignmentTests(unittest.TestCase):
 def fixture(self):
  rows=[{'sourceBook':'ROM','sourceChapter':14,'sourceVerse':str(i),'canonical':None,'alignment':'unsupported','textStatus':'present','text':f'doxology part{i}'}for i in[24,25,26]]
  raw=json.dumps(rows).encode();manifest={'version':'pinned','hash':{'verses':sha(raw)}};mb=json.dumps(manifest).encode();alignment={'schemaVersion':1,'canonicalReferenceSystem':'KJV','sourceManifestSha256':sha(mb),'sourceCorpusVersion':'pinned','sourceVersesSha256':sha(raw),'alignments':[{'canonicalReference':f'ROM:16:{i+1}','sourceReference':{'book':'ROM','chapter':14,'verse':str(i)},'sourceTextSha256':sha(f'doxology part{i}'.encode())}for i in[24,25,26]]};return rows,alignment,mb,raw
 def test_explicit_three_verse_mapping_preserves_input(self):
  rows,a,mb,raw=self.fixture();before=copy.deepcopy(rows);p=resolve(rows,a,mb,raw);self.assertEqual(p['ROM:16:25'],'doxology part24');self.assertEqual(len(p),3);self.assertEqual(rows,before);self.assertNotIn('ROM:14:24',p)
 def test_wrong_shift_or_duplicate_is_rejected(self):
  for field in ['shift','duplicate']:
   rows,a,mb,raw=self.fixture()
   if field=='shift':a['alignments'][0]['sourceReference']['verse']='25'
   else:a['alignments'][1]['canonicalReference']='ROM:16:25'
   with self.assertRaises(ValueError):resolve(rows,a,mb,raw)
 def test_modified_text_manifest_or_corpus_is_rejected(self):
  for kind in ['text','manifest','corpus']:
   rows,a,mb,raw=self.fixture()
   if kind=='text':rows[0]['text']='changed'
   if kind=='manifest':mb+=b' '
   if kind=='corpus':raw+=b' '
   with self.assertRaises(ValueError):resolve(rows,a,mb,raw)
 def test_existing_canonical_text_cannot_be_overwritten(self):
  rows,a,mb,raw=self.fixture();rows.append({'canonical':{'book':'ROM','chapter':16,'verse':25},'text':'existing'})
  with self.assertRaises(ValueError):resolve(rows,a,mb,raw)
 def test_bundled_mapping_uses_verified_literal_source(self):
  p=m['load_primary'](ROOT);self.assertTrue(p['ROM:16:25'].startswith('Now to him who is able'));self.assertIn('all the nations',p['ROM:16:26']);self.assertIn('only wise God',p['ROM:16:27']);self.assertNotIn('ROM:14:24',p)
if __name__=='__main__':unittest.main()
