import './diagnostics/no-external-network.cjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build } from 'esbuild';
process.env.CLOUDFLARE_CF_FETCH_ENABLED = 'false';
const { Miniflare, convertV4MiniflareOptions } = await import('miniflare');
test(
  'actual workerd Free dispatch needs no certificate tables and retains atomic single dispatch',
  { timeout: 120000 },
  async (t) => {
    const temp = await mkdtemp(join(tmpdir(), 'bible-free-quota-'));
    let runtime,
      external = 0;
    t.after(async () => {
      await runtime?.dispose();
      await rm(temp, { recursive: true, force: true });
    });
    await build({
      stdin: {
        contents: `import{loadBudgetAuthority,estimateModelReservation}from'./apps/api/src/budget.ts';import{budgetDispatchGuard}from'./apps/api/src/budget-dispatch.ts';import{DEFAULT_MODEL_ID}from'./packages/ai-harness/src/index.ts';let identity;export default{async fetch(request,env){if(new URL(request.url).pathname==='/capture'){identity=estimateModelReservation(env,DEFAULT_MODEL_ID,512,await loadBudgetAuthority(env,[DEFAULT_MODEL_ID]),1000).dispatchIdentity;return Response.json({budgetDay:identity.budgetDay});}const g=budgetDispatchGuard(env,identity);const row=await env.DB.prepare('UPDATE dispatch_records SET dispatched=1 WHERE id=1 AND dispatched=0 AND '+g.sql+' RETURNING id').bind(...g.params).first();return Response.json({dispatched:!!row});}}`,
        resolveDir: new URL('../', import.meta.url).pathname,
        sourcefile: 'free-runtime-entry.ts',
      },
      outfile: join(temp, 'worker.mjs'),
      bundle: true,
      format: 'esm',
      platform: 'browser',
      external: ['node:*'],
      conditions: ['workerd', 'browser'],
      logLevel: 'silent',
    });
    runtime = new Miniflare(
      convertV4MiniflareOptions({
        rootPath: temp,
        modulesRoot: temp,
        modules: true,
        scriptPath: join(temp, 'worker.mjs'),
        compatibilityDate: '2026-10-13',
        compatibilityFlags: ['nodejs_compat'],
        bindings: {
          ...JSON.parse(
            await readFile(new URL('../apps/api/wrangler.jsonc', import.meta.url), 'utf8'),
          ).vars,
          AI_BUDGET_MODE: 'free-provider-hard-stop',
        },
        d1Databases: { DB: 'quota-test' },
        cf: false,
        host: '127.0.0.1',
        port: 0,
        inspectorPort: 0,
        outboundService: () => {
          external++;
          return new Response('denied', { status: 503 });
        },
      }),
    );
    const db = await runtime.getD1Database('DB');
    await db
      .prepare('CREATE TABLE dispatch_records(id INTEGER PRIMARY KEY,dispatched INTEGER NOT NULL)')
      .run();
    await db.prepare('INSERT INTO dispatch_records VALUES(1,0)').run();
    const capture = await runtime.dispatchFetch('http://local/capture');
    assert.equal(capture.status, 200);
    assert.match((await capture.json()).budgetDay, /^\d{4}-\d{2}-\d{2}$/);
    const results = await Promise.all([
      runtime.dispatchFetch('http://local/run'),
      runtime.dispatchFetch('http://local/run'),
    ]);
    const values = await Promise.all(results.map((r) => r.json()));
    assert.equal(values.filter((v) => v.dispatched).length, 1);
    assert.equal(
      (await (await runtime.dispatchFetch('http://local/run')).json()).dispatched,
      false,
    );
    assert.equal(external, 0);
  },
);
