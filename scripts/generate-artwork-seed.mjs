import { readFileSync } from 'node:fs';
import { materialSchema } from '../packages/core/src/materials.ts';
import { generatedMigration } from './generated-migration.mjs';

const cards = JSON.parse(
  readFileSync(new URL('../packages/core/fixtures/artwork-catalog.json', import.meta.url), 'utf8'),
).map((card) => materialSchema.parse(card));
for (const path of [
  '../apps/ios/Tests/Fixtures/artwork-catalog.json',
  '../apps/ios/UITests/Fixtures/artwork-catalog.json',
]) {
  const fixture = JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
  if (
    JSON.stringify(fixture) !==
    JSON.stringify(
      JSON.parse(
        readFileSync(
          new URL('../packages/core/fixtures/artwork-catalog.json', import.meta.url),
          'utf8',
        ),
      ),
    )
  )
    throw Error('Native artwork test fixtures differ from the reviewed catalog.');
}
const legacy = JSON.parse(
  readFileSync(new URL('../packages/core/fixtures/source-cards.json', import.meta.url), 'utf8'),
);
const ids = new Set(legacy.map((card) => card.id));
const objects = new Set(
  legacy.filter((card) => card.kind === 'artwork').map((card) => card.details.objectUrl),
);
const quote = (value) => "'" + String(value).replaceAll("'", "''") + "'";
const values = [];
let sql =
  '-- Reviewed public-domain artwork catalog; editorial scene mappings: docs/artwork/catalog-review.json.\n';
for (const card of cards) {
  if (
    card.kind !== 'artwork' ||
    !card.reviewed ||
    card.rightsStatus !== 'approved' ||
    !card.details.media ||
    ids.has(card.id) ||
    objects.has(card.details.objectUrl)
  )
    throw Error(
      'Artwork catalog must contain unique approved, illustrated works without legacy collisions.',
    );
  ids.add(card.id);
  objects.add(card.details.objectUrl);
  values.push(
    '(' +
      [
        card.id,
        card.kind,
        card.spoilerEnd.book,
        JSON.stringify(card),
        card.version,
        card.rightsStatus,
        1,
      ]
        .map(quote)
        .join(',') +
      ')',
  );
}
sql +=
  'INSERT INTO public_materials(id,kind,book,data_json,version,rights_status,active) VALUES\n' +
  values.join(',\n') +
  ' ON CONFLICT(id) DO UPDATE SET kind=excluded.kind,book=excluded.book,data_json=excluded.data_json,version=excluded.version,rights_status=excluded.rights_status,active=excluded.active WHERE public_materials.data_json<>excluded.data_json OR public_materials.version<>excluded.version OR public_materials.rights_status<>excluded.rights_status OR public_materials.active<>excluded.active;\n';
generatedMigration('0026_reviewed_artwork_catalog.sql', sql);
console.log('Validated ' + cards.length + ' distinct illustrated artworks.');
