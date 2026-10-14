import {
  readBundledScriptureAssetInputs,
  planScriptureAssets,
} from '../../../../scripts/build-scripture-assets.mjs';
import type { TestDatabase } from './db';
import { SCRIPTURE_ASSET_INDEX_SHA256 } from '../../src/scripture-assets-pin';
let files: Map<string, Buffer> | undefined;
export function realAssetFiles() {
  if (!files)
    files = new Map(
      planScriptureAssets(readBundledScriptureAssetInputs()).files.map((file) => [
        file.path,
        Buffer.from(file.contents),
      ]),
    );
  return files;
}
export function seedAssetCorpus(db: TestDatabase) {
  const input = readBundledScriptureAssetInputs(),
    manifest = JSON.parse(input.manifest.toString());
  db.sqlite
    .prepare(
      `INSERT INTO scripture_corpora(id,version,edition,language,license,manifest_sha256,manifest_json,expected_verses,created_at,storage_type,asset_index_sha256) VALUES(?,?,?,'en','public-domain',?,?,?,1,'assets',?)`,
    )
    .run(
      manifest.corpusId,
      manifest.version,
      manifest.edition,
      'd2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e',
      input.manifest.toString(),
      manifest.verseCount,
      SCRIPTURE_ASSET_INDEX_SHA256,
    );
  db.sqlite
    .prepare("UPDATE scripture_corpora SET state='ready',rights_status='approved',active=1")
    .run();
  return manifest;
}
export function realAssetBinding(calls: string[] = []) {
  return {
    async fetch(request: Request) {
      const path = new URL(request.url).pathname;
      calls.push(path);
      const bytes = realAssetFiles().get(path);
      return bytes
        ? new Response(new Uint8Array(bytes), {
            headers: { 'content-type': 'application/json', 'content-length': String(bytes.length) },
          })
        : new Response('missing', { status: 404 });
    },
  };
}
