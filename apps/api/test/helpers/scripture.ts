import { TRUSTED_PRIMARY_TEXT_MANIFESTS } from '@bible/ai-harness';
import type { TestDatabase } from './db';
/** Synthetic DB fixture only. Production ingestion must validate the complete pinned artifacts. */
export function seedScripture(
  db: TestDatabase,
  verses: { book: string; chapter: number; verse: number; text: string }[],
  anomalies: Record<string, unknown> = {},
) {
  const pin = TRUSTED_PRIMARY_TEXT_MANIFESTS[0];
  if (!pin) throw Error('The independently verified public corpus pin is required.');
  db.sqlite
    .prepare(
      `INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at) VALUES(?,?,?,'en','public-domain',?,?,?,1)`,
    )
    .run(
      pin.corpusId,
      pin.sourceVersion,
      pin.edition,
      pin.manifestSha256,
      JSON.stringify(anomalies),
      verses.length,
    );
  const insert = db.sqlite.prepare(
    `INSERT INTO scripture_verses(corpus_id,corpus_version,source_id,source_book,source_chapter,source_verse,book,chapter,verse,text,alignment,text_status) VALUES(?,?,?,?,?,?,?,?,?,?,'canonical-compatible',?)`,
  );
  for (const v of verses)
    insert.run(
      pin.corpusId,
      pin.sourceVersion,
      `${pin.corpusId}:${v.book}:${v.chapter}:${v.verse}`,
      v.book,
      v.chapter,
      String(v.verse),
      v.book,
      v.chapter,
      v.verse,
      v.text,
      v.text ? 'present' : 'empty',
    );
  db.sqlite
    .prepare(
      "UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1 WHERE id=? AND version=?",
    )
    .run(pin.corpusId, pin.sourceVersion);
  return pin;
}
