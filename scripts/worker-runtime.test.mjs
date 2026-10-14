import './diagnostics/no-external-network.cjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createHash, randomUUID, generateKeyPairSync, sign } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { build } from 'esbuild';
import { planScriptureAssets, readBundledScriptureAssetInputs } from './build-scripture-assets.mjs';
import { pinnedAssetRegistration } from './scripture-assets-config.mjs';

process.env.CLOUDFLARE_CF_FETCH_ENABLED = 'false';
const { Miniflare, convertV4MiniflareOptions } = await import('miniflare');
const root = new URL('../', import.meta.url);
async function files(dir) {
  const result = [];
  for (const item of await readdir(dir, { withFileTypes: true })) {
    const path = join(dir, item.name);
    if (item.isDirectory()) result.push(...(await files(path)));
    else result.push(path);
  }
  return result;
}

test(
  'actual workerd executes isolated authenticated D1 reading and source-only routes',
  { timeout: 120_000 },
  async (t) => {
    const temp = await mkdtemp(join(tmpdir(), 'bible-workerd-smoke-'));
    let runtime;
    t.after(async () => {
      await runtime?.dispose();
      await rm(temp, { recursive: true, force: true });
    });
    const config = JSON.parse(await readFile(new URL('apps/api/wrangler.jsonc', root), 'utf8'));
    await build({
      entryPoints: [new URL('apps/api/src/index.ts', root).pathname],
      outfile: join(temp, 'worker.mjs'),
      bundle: true,
      format: 'esm',
      platform: 'browser',
      external: ['node:*'],
      conditions: ['workerd', 'browser'],
      logLevel: 'silent',
    });
    const assetFiles = new Map(
      planScriptureAssets(readBundledScriptureAssetInputs()).files.map((file) => [
        file.path,
        file.contents,
      ]),
    );
    const assetRequests = [];
    let externalRequests = 0;
    const options = {
      rootPath: temp,
      modulesRoot: temp,
      modules: true,
      scriptPath: join(temp, 'worker.mjs'),
      compatibilityDate: config.compatibility_date,
      compatibilityFlags: config.compatibility_flags,
      bindings: config.vars,
      d1Databases: { DB: 'runtime-smoke' },
      serviceBindings: {
        SCRIPTURE_ASSETS: (request) => {
          const path = new URL(request.url).pathname;
          assetRequests.push(path);
          const content = assetFiles.get(path);
          return content === undefined
            ? new Response('missing', { status: 404 })
            : new Response(content, {
                headers: {
                  'content-type': 'application/json',
                  'content-length': String(Buffer.byteLength(content)),
                },
              });
        },
      },
      resourcePersistencePath: join(temp, 'd1'),
      cf: false,
      host: '127.0.0.1',
      port: 0,
      inspectorPort: 0,
      outboundService: () => {
        externalRequests++;
        return new Response('External network denied', { status: 503 });
      },
    };
    runtime = new Miniflare(convertV4MiniflareOptions(options));
    await (await runtime.getD1Database('DB')).prepare('SELECT 1').first();
    await runtime.dispose();
    runtime = undefined;
    const databases = (await files(join(temp, 'd1'))).filter(
      (path) =>
        path.includes('/miniflare-D1DatabaseObject/') && /\/[a-f0-9]{64}\.sqlite$/.test(path),
    );
    assert.equal(databases.length, 1);
    const db = new DatabaseSync(databases[0]);
    try {
      db.exec('PRAGMA foreign_keys=ON');
      const migrations = new URL('apps/api/migrations/', root);
      for (const name of (await readdir(migrations)).filter((name) => name.endsWith('.sql')).sort())
        db.exec(await readFile(new URL(name, migrations), 'utf8'));
      db.exec(pinnedAssetRegistration().sql);
      const now = Math.floor(Date.now() / 1000);
      for (const [id, token] of [
        ['alice', 'synthetic-alice-session'],
        ['bob', 'synthetic-bob-session'],
      ]) {
        db.prepare('INSERT INTO users(id,display_name,role,created_at) VALUES(?,?,?,?)').run(
          id,
          'Synthetic runtime reader',
          'member',
          now,
        );
        db.prepare(
          'INSERT INTO sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)',
        ).run(createHash('sha256').update(token).digest('base64url'), id, now + 3600, now);
      }
    } finally {
      db.close();
    }
    runtime = new Miniflare(convertV4MiniflareOptions(options));
    const request = (path, method = 'GET', body, token = 'synthetic-alice-session') =>
      runtime.dispatchFetch(`http://localhost${path}`, {
        method,
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
    assert.equal((await request('/health')).status, 200);
    assert.equal((await request('/v1/me', 'GET', undefined, 'unknown')).status, 401);
    const importedResponse = await request('/v1/imports', 'POST', {
      idempotencyKey: randomUUID(),
      sharedText: '使徒18:18 JCB',
    });
    assert.equal(importedResponse.status, 201, await importedResponse.clone().text());
    const imported = await importedResponse.json();
    assert.equal(
      (await request(`/v1/imports/${imported.id}`, 'GET', undefined, 'synthetic-bob-session'))
        .status,
      404,
    );
    const reading = await request(`/v1/imports/${imported.id}/reading`);
    assert.equal(reading.status, 200, await reading.clone().text());
    assert.equal((await reading.json()).cache, 'public-miss');
    assert.equal(
      (await (await request(`/v1/imports/${imported.id}/reading`)).json()).cache,
      'public-hit',
    );
    const conversationResponse = await request('/v1/conversations', 'POST', {
      importId: imported.id,
    });
    assert.equal(conversationResponse.status, 201, await conversationResponse.clone().text());
    const conversation = await conversationResponse.json();
    const questionPayload = {
      requestId: randomUUID(),
      question: 'この節の資料は？',
      sourceOnly: true,
    };
    const answerResponse = await request(
      `/v1/conversations/${conversation.id}/questions`,
      'POST',
      questionPayload,
    );
    assert.equal(answerResponse.status, 200, await answerResponse.clone().text());
    const answer = await answerResponse.json();
    assert.equal(answer.result.modelInvoked, false);
    assert.equal(answer.result.mode, 'source-only');
    const denied = await request(`/v1/conversations/${conversation.id}/questions`, 'POST', {
      requestId: randomUUID(),
      question: 'この節の意味は？',
    });
    assert.equal(denied.status, 503);
    assert.equal((await denied.json()).error.code, 'ai_not_connected');
    const replay = await request(
      `/v1/conversations/${conversation.id}/questions`,
      'POST',
      questionPayload,
    );
    assert.equal(replay.status, 200);
    assert.deepEqual(await replay.json(), answer);
    const liveDB = await runtime.getD1Database('DB');
    assert.deepEqual(
      await liveDB
        .prepare('SELECT COUNT(*) AS n FROM messages WHERE conversation_id=?')
        .bind(conversation.id)
        .first(),
      { n: 2 },
    );
    const citationId = answer.result.citations.find((citation) => citation.sourceId)?.sourceId;
    assert.ok(citationId, 'Source-only answer must cite seeded material');
    await liveDB
      .prepare('UPDATE public_sources SET rights_status=? WHERE id=?')
      .bind('revoked', citationId)
      .run();
    const detail = await (await request(`/v1/conversations/${conversation.id}`)).json();
    assert.equal(
      detail.messages.find((message) => message.role === 'user').content.text,
      'この節の資料は？',
    );
    assert.equal(
      detail.messages.find((message) => message.role === 'assistant').content.hidden,
      true,
    );
    const afterRevocation = await (await request(`/v1/imports/${imported.id}/reading`)).json();
    assert.equal(afterRevocation.cache, 'public-miss');
    assert.ok(
      !afterRevocation.overview.citations.some((citation) => citation.sourceId === citationId),
    );
    assert.equal((await request('/v1/logout', 'POST')).status, 204);
    assert.equal((await request('/v1/me')).status, 401);
    await signedLogin(runtime, liveDB, config.vars);
    const genesisResponse = await request(
      '/v1/imports',
      'POST',
      { idempotencyKey: randomUUID(), sharedText: 'Genesis 1:1-3 WEB' },
      'synthetic-bob-session',
    );
    assert.equal(genesisResponse.status, 201);
    const genesis = await genesisResponse.json();
    const scriptureResponse = await request(
      `/v1/imports/${genesis.id}/scripture`,
      'GET',
      undefined,
      'synthetic-bob-session',
    );
    assert.equal(scriptureResponse.status, 200, await scriptureResponse.clone().text());
    const scripture = await scriptureResponse.json();
    assert.equal(scripture.available, true);
    assert.equal(scripture.corpus.editorialReview, 'unreviewed');
    assert.deepEqual(
      scripture.items.map((item) => item.id),
      ['webp:GEN:1:1', 'webp:GEN:1:2', 'webp:GEN:1:3'],
    );
    assert.equal(
      scripture.items[0].text,
      'In the beginning, God created the heavens and the earth.',
    );
    assert.ok(assetRequests.some((path) => path.endsWith('/GEN/1.json')));
    assert.deepEqual(await liveDB.prepare('SELECT COUNT(*) AS n FROM scripture_verses').first(), {
      n: 0,
    });
    const beforeDirect = assetRequests.length;
    assert.equal(
      (await runtime.dispatchFetch(`http://localhost${assetRequests.at(-1)}`)).status,
      404,
    );
    assert.equal(assetRequests.length, beforeDirect);
    await liveDB
      .prepare("UPDATE scripture_corpora SET active=0,rights_status='revoked' WHERE id='webp'")
      .run();
    const revoked = await (
      await request(
        `/v1/imports/${genesis.id}/scripture`,
        'GET',
        undefined,
        'synthetic-bob-session',
      )
    ).json();
    assert.equal(revoked.available, false);

    assert.equal(externalRequests, 0);
  },
);

async function signedLogin(runtime, db, config) {
  const pair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = pair.publicKey.export({ format: 'jwk' });
  const key = Buffer.concat([
    Buffer.from([0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20]),
    Buffer.from(jwk.x, 'base64url'),
    Buffer.from([0x22, 0x58, 0x20]),
    Buffer.from(jwk.y, 'base64url'),
  ]);
  const credentialId = Buffer.from(randomUUID()).toString('base64url');
  await db
    .prepare(
      'INSERT INTO credentials(id,user_id,public_key,counter,transports_json,device_type,backed_up,created_at) VALUES(?,?,?,?,?,?,?,?)',
    )
    .bind(
      credentialId,
      'alice',
      key.toString('base64url'),
      0,
      '[]',
      'singleDevice',
      0,
      Math.floor(Date.now() / 1000),
    )
    .run();
  const verifier = 'synthetic-runtime-pkce-verifier-'.padEnd(64, 'x');
  const state = Buffer.from(randomUUID()).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  const authorize = await runtime.dispatchFetch(
    `http://localhost/auth/authorize?state=${state}&code_challenge=${challenge}&code_challenge_method=S256`,
  );
  assert.equal(authorize.status, 200);
  const cookie = authorize.headers.get('set-cookie').split(';')[0];
  assert.match(authorize.headers.get('set-cookie'), /HttpOnly/);
  assert.match(authorize.headers.get('set-cookie'), /SameSite=Strict/);
  const post = (path, body, origin = config.AUTH_ORIGIN) =>
    runtime.dispatchFetch(`http://localhost${path}`, {
      method: 'POST',
      headers: { origin, cookie, 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
  assert.equal(
    (await post('/auth/options', { mode: 'login' }, 'https://invalid.example')).status,
    403,
  );
  const optionsResponse = await post('/auth/options', { mode: 'login' });
  assert.equal(optionsResponse.status, 200);
  const { options } = await optionsResponse.json();
  const clientDataJSON = Buffer.from(
    JSON.stringify({
      type: 'webauthn.get',
      challenge: options.challenge,
      origin: config.AUTH_ORIGIN,
      crossOrigin: false,
    }),
  );
  const counter = Buffer.alloc(4);
  counter.writeUInt32BE(1);
  const authenticatorData = Buffer.concat([
    createHash('sha256').update(config.RP_ID).digest(),
    Buffer.from([0x05]),
    counter,
  ]);
  const signature = sign(
    'sha256',
    Buffer.concat([authenticatorData, createHash('sha256').update(clientDataJSON).digest()]),
    pair.privateKey,
  );
  const response = {
    id: credentialId,
    rawId: credentialId,
    type: 'public-key',
    clientExtensionResults: {},
    response: {
      clientDataJSON: clientDataJSON.toString('base64url'),
      authenticatorData: authenticatorData.toString('base64url'),
      signature: signature.toString('base64url'),
      userHandle: null,
    },
  };
  const verified = await post('/auth/verify', { response });
  assert.equal(verified.status, 200, await verified.clone().text());
  const callback = new URL((await verified.json()).callback);
  assert.equal(callback.protocol, 'biblecompanion:');
  assert.equal(callback.searchParams.get('state'), state);
  assert.equal((await post('/auth/verify', { response })).status, 401);
  const code = callback.searchParams.get('code');
  const exchanged = await Promise.all([
    post('/auth/token', { code, codeVerifier: verifier }),
    post('/auth/token', { code, codeVerifier: verifier }),
  ]);
  assert.deepEqual(exchanged.map((item) => item.status).sort(), [200, 401]);
  const session = await exchanged.find((item) => item.status === 200).json();
  const me = await runtime.dispatchFetch('http://localhost/v1/me', {
    headers: { authorization: `Bearer ${session.accessToken}` },
  });
  assert.equal(me.status, 200);
  assert.equal((await me.json()).user.id, 'alice');
  assert.deepEqual(
    await db.prepare('SELECT counter FROM credentials WHERE id=?').bind(credentialId).first(),
    { counter: 1 },
  );
}
