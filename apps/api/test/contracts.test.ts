import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fixture } from './helpers/fixtures';
import { fileURLToPath } from 'node:url';
import { z } from 'zod';
import { passageSchema } from '@bible/core';
import { app } from '../src/index';
import { testEnv, seedUser, TestDatabase } from './helpers/db';
import { seedScripture } from './helpers/scripture';
const fixtures = fileURLToPath(new URL('../../../docs/fixtures/', import.meta.url));
const importDTO = z.object({
  id: z.string().uuid(),
  idempotencyKey: z.string().uuid(),
  ranges: z.array(passageSchema),
  translation: z.string().nullable(),
  sourceUrl: z.string().nullable(),
  createdAt: z.number().int(),
});
const conversationDTO = z.object({
  id: z.string().uuid(),
  importId: z.string().uuid(),
  passage: passageSchema,
  readingBoundary: passageSchema,
  spoilerAllowed: z.boolean(),
  createdAt: z.number().int(),
});
const readingDTO = z.object({
  checkedAt: z.number().int(),
  offlineCache: z.object({
    eligible: z.boolean(),
    maxAgeSeconds: z.number().int(),
    reason: z.string(),
    allowedFields: z.array(z.literal('overview')),
    dependencies: z.array(z.object({ id: z.string(), version: z.string() })),
    policyVersion: z.literal(1),
  }),
  passage: passageSchema,
  translation: z.string().nullable(),
  spoilerAllowed: z.boolean(),
  sourceVersion: z.string(),
  overview: z.object({
    contentKind: z.enum(['literal-primary-text', 'curated-reference']),
    noticeJa: z.string(),
    referenceSystem: z.object({
      canon: z.literal('protestant-66'),
      versification: z.literal('standard-kjv'),
      requestedTranslation: z.string().nullable(),
      translationAlignment: z.literal('unverified'),
      noticeJa: z.string(),
    }),
    text: z.string(),
    claims: z.array(z.unknown()),
    citations: z.array(z.unknown()),
    mode: z.literal('source-only'),
    modelInvoked: z.literal(false),
  }),
  sources: z.array(z.unknown()),
  people: z.array(z.unknown()),
  places: z.array(z.unknown()),
  artworks: z.array(z.unknown()),
  materialNotice: z.string(),
  cache: z.enum(['public-hit', 'public-miss']),
});
describe('native response contracts', () => {
  it('produces real endpoint JSON fixtures without credentials', async () => {
    const env = testEnv(),
      user = await seedUser(env, crypto.randomUUID(), 'owner');
    const me = await (await app.request('/v1/me', { headers: user.headers }, env)).json();
    fixture(
      'ai-policy',
      await (await app.request('/v1/me/ai-policy', { headers: user.headers }, env)).json(),
    );
    expect(
      z
        .object({
          user: z.object({
            id: z.string().uuid(),
            display_name: z.string(),
            role: z.enum(['owner', 'member']),
          }),
        })
        .safeParse(me).success,
    ).toBe(true);
    fixture('me', me);
    const imported = await (
      await app.request(
        '/v1/imports',
        {
          method: 'POST',
          headers: user.headers,
          body: JSON.stringify({
            idempotencyKey: crypto.randomUUID(),
            sharedText: '使徒18:12–18 JCB',
          }),
        },
        env,
      )
    ).json();
    const row = importDTO.parse(imported);
    fixture('import', row);
    const subset = {
      book: 'ACT',
      start: { chapter: 18, verse: 17 },
      end: { chapter: 18, verse: 17 },
    };
    const created = await app.request(
      '/v1/conversations',
      {
        method: 'POST',
        headers: user.headers,
        body: JSON.stringify({ importId: row.id, passage: subset }),
      },
      env,
    );
    expect(created.status).toBe(201);
    const conversation = conversationDTO.parse(await created.json());
    expect(conversation.passage.end.verse).toBe(17);
    expect(conversation.readingBoundary.end.verse).toBe(18);
    fixture('conversation', conversation);
    const reading = readingDTO.parse(
      await (
        await app.request(`/v1/imports/${row.id}/reading`, { headers: user.headers }, env)
      ).json(),
    );
    fixture('reading', reading);
    const manifest = await (
      await app.request('/v1/content-manifest', { headers: user.headers }, env)
    ).json();
    fixture('content-manifest', manifest);
    const answer = (await (
      await app.request(
        `/v1/conversations/${conversation.id}/questions`,
        {
          method: 'POST',
          headers: user.headers,
          body: JSON.stringify({
            requestId: crypto.randomUUID(),
            question: 'ソステネは誰？',
            sourceOnly: true,
          }),
        },
        env,
      )
    ).json()) as { status: string; result: { answer: string; modelInvoked: boolean } };
    expect(answer.status).toBe('complete');
    expect(answer.result.modelInvoked).toBe(false);
    fixture('question-result', answer);
    fixture(
      'conversation-detail',
      await (
        await app.request('/v1/conversations/' + conversation.id, { headers: user.headers }, env)
      ).json(),
    );
    const catalog = (await (
      await app.request('/v1/developer/models', { headers: user.headers }, env)
    ).json()) as { models: { enabled: boolean }[] };
    expect(catalog.models.every((m) => !m.enabled)).toBe(true);
    fixture('model-catalog', catalog);
    fixture(
      'conversation-list',
      await (await app.request('/v1/conversations', { headers: user.headers }, env)).json(),
    );
    const snapshotResponse = await app.request(
      '/v1/me/export/snapshots',
      { method: 'POST', headers: user.headers, body: '{}' },
      env,
    );
    expect(snapshotResponse.status).toBe(201);
    const snapshot = (await snapshotResponse.json()) as { snapshotId: string };
    fixture('export-snapshot', snapshot);
    const pageResponse = await app.request(
      '/v1/me/export/pages?snapshotId=' + snapshot.snapshotId + '&section=messages',
      { headers: user.headers },
      env,
    );
    expect(pageResponse.status).toBe(200);
    fixture('export-page', await pageResponse.json());
    const deletedReading = await app.request(
      '/v1/me/reading-data',
      {
        method: 'DELETE',
        headers: user.headers,
        body: JSON.stringify({ confirmation: 'DELETE_MY_READING_DATA' }),
      },
      env,
    );
    expect(deletedReading.status).toBe(200);
    fixture('reading-data-deleted', await deletedReading.json());
    const deletedAccount = await app.request(
      '/v1/me',
      {
        method: 'DELETE',
        headers: user.headers,
        body: JSON.stringify({ confirmation: 'DELETE_MY_ACCOUNT' }),
      },
      env,
    );
    expect(deletedAccount.status).toBe(200);
    fixture('account-deleted', await deletedAccount.json());
  });
  it('documents every externally consumed API operation', () => {
    const spec = JSON.parse(
      readFileSync(fileURLToPath(new URL('../../../docs/openapi.json', import.meta.url)), 'utf8'),
    ) as { openapi: string; paths: Record<string, unknown> };
    expect(spec.openapi).toBe('3.1.0');
    for (const path of [
      '/auth/authorize',
      '/auth/token',
      '/v1/imports',
      '/v1/imports/{id}/reading',
      '/v1/conversations',
      '/v1/conversations/{id}/questions',
      '/v1/developer/comparisons',
    ])
      expect(spec.paths[path]).toBeDefined();
  });
});

describe('route inventory cannot drift from OpenAPI', () => {
  it('documents every registered JSON endpoint and no nonexistent endpoint', () => {
    const spec = JSON.parse(
      readFileSync(fileURLToPath(new URL('../../../docs/openapi.json', import.meta.url)), 'utf8'),
    ) as { paths: Record<string, Record<string, unknown>> };
    const runtime = new Set(
      app.routes
        .filter(
          (r) =>
            r.method !== 'ALL' &&
            (r.path.startsWith('/v1/') || r.path.startsWith('/auth/') || r.path.startsWith('/share/') || r.path.startsWith('/public/')) &&
            !['/auth/client.js', '/auth/style.css', '/auth/authorize'].includes(r.path),
        )
        .map((r) => r.method.toLowerCase() + ' ' + r.path.replace(/:([A-Za-z0-9_]+)/g, '{$1}')),
    );
    const documented = new Set(
      Object.entries(spec.paths)
        .flatMap(([path, methods]) => Object.keys(methods).map((method) => method + ' ' + path))
        .filter((x) => !x.endsWith('/auth/authorize') && !x.endsWith('/health')),
    );
    expect([...runtime].filter((x) => !documented.has(x))).toEqual([]);
    expect([...documented].filter((x) => !runtime.has(x))).toEqual([]);
  });
});

describe('error and content-type contracts', () => {
  it('returns private-safe JSON for unknown routes and validation errors', async () => {
    const env = testEnv(),
      user = await seedUser(env);
    for (const request of [
      app.request('/v1/unknown-secret-text?token=do-not-echo', { headers: user.headers }, env),
      app.request(
        '/v1/imports',
        { method: 'POST', headers: user.headers, body: '{"private":"do-not-echo"}' },
        env,
      ),
    ]) {
      const response = await request;
      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(response.headers.get('content-type')).toContain('application/json');
      expect(response.headers.get('cache-control')).toBe('no-store');
      const value = await response.json();
      expect(
        z.object({ error: z.object({ code: z.string(), message: z.string() }) }).safeParse(value)
          .success,
      ).toBe(true);
      expect(JSON.stringify(value)).not.toContain('do-not-echo');
    }
  });
});

it('produces primary-text and unavailable scripture page fixtures from actual routes', async () => {
  const db = new TestDatabase(),
    env = testEnv(db),
    user = await seedUser(env);
  const passage = { book: 'GEN', start: { chapter: 1, verse: 1 }, end: { chapter: 1, verse: 3 } };
  const created = await app.request(
    '/v1/imports',
    {
      method: 'POST',
      headers: user.headers,
      body: JSON.stringify({
        idempotencyKey: crypto.randomUUID(),
        ranges: [passage],
        translation: 'JCB',
      }),
    },
    env,
  );
  const row = (await created.json()) as { id: string };
  const get = (route: string) =>
    app.request(`/v1/imports/${row.id}/${route}`, { headers: user.headers }, env);
  fixture('scripture-unavailable', await (await get('scripture')).json());
  seedScripture(db, [
    {
      book: 'GEN',
      chapter: 1,
      verse: 1,
      text: 'In the beginning, God created the heavens and the earth.',
    },
    {
      book: 'GEN',
      chapter: 1,
      verse: 2,
      text: 'The earth was formless and empty. Darkness was on the surface of the deep and God’s Spirit was hovering over the surface of the waters.',
    },
    {
      book: 'GEN',
      chapter: 1,
      verse: 3,
      text: 'God said, “Let there be light,” and there was light.',
    },
  ]);
  const page = await get('scripture');
  expect(page.status).toBe(200);
  fixture('scripture-page', await page.json());
  fixture('reading-primary-text', readingDTO.parse(await (await get('reading')).json()));
});
