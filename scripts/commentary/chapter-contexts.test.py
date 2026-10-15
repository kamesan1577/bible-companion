#!/usr/bin/env python3
import unittest,runpy,re,html,json
from pathlib import Path
R=Path(__file__).resolve().parents[2];mod=runpy.run_path(str(Path(__file__).with_name('chapter-contexts.py')))
def plain(s):return html.unescape(re.sub('<[^>]+>','',s)).strip()
class ChapterContextsTests(unittest.TestCase):
 def setUp(self):
  self.counts=json.loads((R/'packages/core/src/verse-counts.json').read_text());self.names={'2SA':'II Samuel','PSA':'Psalms'};self.markup='<title>CHAPTER 22</title><reference osisRef="2Sam.22.1-2Sam.22.51">2Sa 22:1-51</reference>. David\'s Psalm of Thanksgiving. The song contained in this chapter is the same as the eighteenth Psalm, where the full commentary will be given [see on <reference osisRef="Ps.18.1">Psa 18:1</reference>, &amp;c.].'
 def build(self,rows):return mod['make_contexts'](rows,'JFB',self.names,self.counts,plain)
 def test_chapter_zero_is_preserved_as_one_context_not_51_independent_notes(self):
  rows=self.build([('II Samuel 22:0',self.markup)]);self.assertEqual(len(rows),1);r=rows[0];self.assertEqual(r['kind'],'chapter-context');self.assertEqual(r['ranges'][0]['start'],{'chapter':22,'verse':1});self.assertEqual(r['ranges'][0]['end'],{'chapter':22,'verse':51});self.assertIn('full commentary',r['originalText']);self.assertFalse(r['spoilerSafe'])
 def test_parallel_psalm_is_navigation_metadata_not_transitive_verse_coverage(self):
  rows=self.build([('II Samuel 22:0',self.markup)]);r=rows[0]['crossReferences'][0];self.assertEqual(r['sourceReference'],'Ps.18.1');self.assertEqual(r['passage']['book'],'PSA');self.assertEqual(r['passage']['end'],{'chapter':18,'verse':50});self.assertIn('not verse alignment',r['relation']);coords=mod['scope_coordinates'](rows);self.assertEqual(len(coords),51);self.assertIn('2SA:22:1',coords);self.assertFalse(any(x.startswith('PSA:')for x in coords))
 def test_book_introduction_and_empty_or_invalid_chapter_are_not_expanded(self):
  rows=[('II Samuel 0:0',self.markup),('II Samuel 25:0',self.markup),('II Samuel 22:0','<chapter/>'),('II Samuel 22:1',self.markup)];self.assertEqual(self.build(rows),[])
 def test_context_identity_is_stable_and_locator_bound(self):
  a=self.build([('II Samuel 22:0',self.markup)])[0];b=self.build([('II Samuel 23:0',self.markup)])[0];self.assertEqual(a['id'],self.build([('II Samuel 22:0',self.markup)])[0]['id']);self.assertNotEqual(a['id'],b['id']);self.assertEqual(a['originalMarkupSha256'],b['originalMarkupSha256'])
 def test_unrelated_reference_is_not_automatically_promoted_to_parallel_chapter(self):
  rows=self.build([('II Samuel 21:0',self.markup)]);self.assertEqual(rows[0]['crossReferences'],[]);self.assertEqual(rows[0]['sourceReferences'],['2Sam.22.1-2Sam.22.51','Ps.18.1'])
if __name__=='__main__':unittest.main()
