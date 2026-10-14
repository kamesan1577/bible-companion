import { generatedMigration } from './generated-migration.mjs';
import { readFileSync } from 'node:fs';
import { materialSchema } from '../packages/core/src/materials.ts';
const cards = JSON.parse(
  readFileSync(new URL('../packages/core/fixtures/source-cards.json', import.meta.url), 'utf8'),
).map((card) => materialSchema.parse(card));
const quote = (value) => "'" + String(value).replaceAll("'", "''") + "'";
let sql = '-- Primary-source reviewed people, places and artwork; see docs/card-provenance.md.\n';
for (const card of cards)
  sql +=
    'INSERT OR REPLACE INTO public_materials(id,kind,book,data_json,version,rights_status,active) VALUES(' +
    [
      card.id,
      card.kind,
      card.spoilerEnd.book,
      JSON.stringify(card),
      card.version,
      card.rightsStatus,
      card.reviewed ? 1 : 0,
    ]
      .map(quote)
      .join(',') +
    ');\n';
generatedMigration('0019_reviewed_geography.sql', sql);
console.log('Validated ' + cards.length + ' material inputs.');
