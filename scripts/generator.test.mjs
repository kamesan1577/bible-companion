import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
test('seed generators check deterministically and cannot overwrite existing migration history', () => {
  for (const [script, migration] of [
    ['generate-source-seed.mjs', '0003_reviewed_sources.sql'],
    ['generate-material-seed.mjs', '0010_reviewed_materials.sql'],
  ]) {
    const path = new URL('../apps/api/migrations/' + migration, import.meta.url),
      before = readFileSync(path, 'utf8');
    assert.equal(
      spawnSync(process.execPath, ['scripts/' + script, '--check'], { cwd: root }).status,
      0,
    );
    assert.equal(spawnSync(process.execPath, ['scripts/' + script], { cwd: root }).status, 1);
    assert.equal(
      spawnSync(process.execPath, ['scripts/' + script, '--output', '../escape.sql'], { cwd: root })
        .status,
      1,
    );
    assert.equal(
      spawnSync(process.execPath, ['scripts/' + script, '--check', '--unknown'], { cwd: root })
        .status,
      1,
    );
    assert.equal(readFileSync(path, 'utf8'), before);
  }
});
