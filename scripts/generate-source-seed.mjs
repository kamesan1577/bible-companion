import { generatedMigration } from './generated-migration.mjs';
import { validateSource } from '../packages/ai-harness/src/grounding.ts';
import { ACTS_SOURCES } from '../packages/ai-harness/fixtures/acts-sources.ts';

const quote = (s) => "'" + String(s).replaceAll("'", "''") + "'";
let sql = '-- Reviewed WEB excerpts and original Japanese notes; see docs/DATA-PROVENANCE.md.\n';
for (const s of ACTS_SOURCES) {
  validateSource(s);
  if (s.visibility !== 'public' || s.reviewed !== true || s.license !== 'public-domain')
    throw Error('Initial source seed accepts reviewed public-domain sources only.');
  sql +=
    'INSERT OR REPLACE INTO public_sources(id,book,start_chapter,start_verse,end_chapter,end_verse,kind,title,content_json,version,rights_status,active) VALUES(' +
    [
      s.id,
      s.book,
      s.start.chapter,
      s.start.verse,
      s.end.chapter,
      s.end.verse,
      s.kind,
      s.title,
      JSON.stringify(s),
      s.version,
      'approved',
      1,
    ]
      .map(quote)
      .join(',') +
    ');\n';
}
generatedMigration('0003_reviewed_sources.sql', sql);
console.log('Validated ' + ACTS_SOURCES.length + ' reviewed source inputs.');
