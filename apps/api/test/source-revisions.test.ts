import { describe, it, expect } from 'vitest';
import { testEnv } from './helpers/db';
describe('immutable public citation versions', () => {
  it('requires a new version for semantic corrections while allowing rights revocation', async () => {
    const env = testEnv();
    await expect(
      env.DB.prepare(
        "UPDATE public_sources SET title='Corrected title' WHERE id='act-18-18'",
      ).run(),
    ).rejects.toThrow('source_version_content_conflict');
    await expect(
      env.DB.prepare(
        "UPDATE public_sources SET title='Corrected title',version='corrected-v2' WHERE id='act-18-18'",
      ).run(),
    ).resolves.toBeDefined();
    await expect(
      env.DB.prepare(
        "UPDATE public_sources SET rights_status='revoked' WHERE id='act-18-18'",
      ).run(),
    ).resolves.toBeDefined();
  });
  it('prevents a removed source identity from being reused for different evidence', async () => {
    const env = testEnv();
    await env.DB.prepare('CREATE TEMP TABLE source_copy AS SELECT * FROM public_sources WHERE id=?')
      .bind('act-18-18')
      .run();
    await env.DB.prepare('DELETE FROM public_sources WHERE id=?').bind('act-18-18').run();
    await env.DB.prepare("UPDATE source_copy SET title='Different content'").run();
    await expect(
      env.DB.prepare('INSERT INTO public_sources SELECT * FROM source_copy').run(),
    ).rejects.toThrow('source_version_content_conflict');
  });
});
