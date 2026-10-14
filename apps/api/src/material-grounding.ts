import { compareVerse, type Passage } from '@bible/core';
import { validateSource, type GroundingSource } from '@bible/ai-harness';
import { materialSchema, materialVisible } from '../../../packages/core/src/materials';
/** Original source-checked, server-curated summaries, not external article text or scripture quotations. */
export function materialGroundingSource(
  row: { id: string; book: string; version: string; material_json: string },
  boundary: Passage,
  spoilers: boolean,
): GroundingSource | null {
  try {
    const card = materialSchema.parse(JSON.parse(row.material_json));
    if (
      card.id !== row.id ||
      card.version !== row.version ||
      card.spoilerEnd.book !== row.book ||
      !materialVisible(card, boundary, spoilers)
    )
      return null;
    const start = card.passages.map((p) => p.start).sort(compareVerse)[0];
    const source = {
      id: 'material:' + card.id,
      version: card.version,
      book: row.book,
      start,
      end: { chapter: card.spoilerEnd.chapter, verse: card.spoilerEnd.verse },
      spoilerEnd: { chapter: card.spoilerEnd.chapter, verse: card.spoilerEnd.verse },
      kind: 'commentary',
      title: '確認済み資料解説：' + card.title,
      text: card.summary,
      url: card.provenance[0].url,
      license: 'original-commentary',
      visibility: 'public',
      reviewed: true,
      generationAllowed: true,
      claims: [
        {
          id: 'summary',
          kind: card.kind === 'artwork' ? 'inference' : 'fact',
          text: card.summary,
          evidenceQuote: card.summary,
        },
      ],
      materialProvenance: {
        kind: 'reviewed-material-summary',
        materialId: card.id,
        materialVersion: card.version,
        materialKind: card.kind,
        references: card.provenance,
      },
    };
    validateSource(source);
    return source;
  } catch {
    return null;
  }
}
