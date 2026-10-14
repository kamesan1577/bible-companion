import type { Env } from './types';
import type { Passage } from '@bible/core';
import {
  materialSchema,
  materialVisible,
  projectMaterial,
  type MaterialCard,
} from '../../../packages/core/src/materials';
export async function getMaterials(
  env: Env,
  passage: Passage,
  spoilers = false,
): Promise<MaterialCard[]> {
  const rows = await env.DB.prepare(
    `WITH candidates AS (SELECT id,kind,data_json,version FROM public_materials WHERE book=? AND active=1 AND rights_status='approved' AND length(CAST(data_json AS BLOB))<=65536
     AND EXISTS(SELECT 1 FROM json_each(CASE WHEN json_valid(data_json) THEN data_json ELSE '{"passages":[]}' END,'$.passages') p
       WHERE json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.book')=? AND json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.start.chapter')*1000+json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.start.verse')<=?
       AND json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.end.chapter')*1000+json_extract(CASE WHEN p.type='object' THEN p.value ELSE '{}' END,'$.end.verse')>=?)
     ORDER BY id LIMIT 100), bounded AS (
       SELECT *,SUM(length(CAST(data_json AS BLOB))) OVER(ORDER BY id) AS body_bytes FROM candidates
     ) SELECT id,kind,data_json,version FROM bounded WHERE body_bytes<=1048576 ORDER BY id`,
  )
    .bind(
      passage.book,
      passage.book,
      passage.end.chapter * 1000 + passage.end.verse,
      passage.start.chapter * 1000 + passage.start.verse,
    )
    .all<{ id: string; kind: string; data_json: string; version: string }>();
  const cards: MaterialCard[] = [];
  let bytes = 0;
  for (const row of rows.results) {
    try {
      const card = materialSchema.parse(JSON.parse(row.data_json));
      if (
        card.id === row.id &&
        card.kind === row.kind &&
        card.version === row.version &&
        materialVisible(card, passage, spoilers)
      ) {
        const projected = projectMaterial(card, passage, spoilers);
        const size = new TextEncoder().encode(JSON.stringify(projected)).byteLength;
        if (bytes + size > 1048576) break;
        bytes += size;
        cards.push(projected);
      }
    } catch {
      /* Unverified or corrupt metadata is never displayed. */
    }
  }
  return cards;
}
