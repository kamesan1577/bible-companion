import './diagnostics/no-external-network.cjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { build } from 'esbuild';
process.env.CLOUDFLARE_CF_FETCH_ENABLED = 'false';
const { Miniflare, convertV4MiniflareOptions } = await import('miniflare');
const root = new URL('../', import.meta.url);

test(
  'workerd and D1 enforce frozen slot dispatch CAS, concurrent rotation and revocation locally',
  { timeout: 120000 },
  async (t) => {
    const temp = await mkdtemp(join(tmpdir(), 'bible-slot-runtime-'));
    let runtime,
      externalRequests = 0;
    t.after(async () => {
      await runtime?.dispose();
      await rm(temp, { recursive: true, force: true });
    });
    await build({
      stdin: {
        contents: `
    import { loadBudgetAuthority, estimateModelReservation } from './apps/api/src/budget.ts';
    import { budgetDispatchGuard } from './apps/api/src/budget-dispatch.ts';
    import { DEFAULT_MODEL_ID } from './packages/ai-harness/src/index.ts';
    let identity;
    export default { async fetch(request,env) { try {
      if (new URL(request.url).pathname === '/capture') {
        identity = estimateModelReservation(env,DEFAULT_MODEL_ID,512,await loadBudgetAuthority(env,[DEFAULT_MODEL_ID]),1000).dispatchIdentity;
        return Response.json({generation:identity.generation});
      }
      const guard = budgetDispatchGuard(env,identity);
      const row = await env.DB.prepare('UPDATE dispatch_records SET dispatched=1 WHERE id=1 AND dispatched=0 AND '+guard.sql+' RETURNING id').bind(...guard.params).first();
      return Response.json({dispatched:!!row});
    } catch(e) { return new Response(String(e.stack ?? e),{status:500}); } }};`,
        resolveDir: new URL('../', import.meta.url).pathname,
        sourcefile: 'slot-runtime-entry.ts',
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
          ...JSON.parse(await readFile(new URL('apps/api/wrangler.jsonc', root), 'utf8')).vars,
          AI_BUDGET_MODE: 'free-provider-hard-stop',
          AI_FREE_RECEIPT_MODE: 'slot',
          AI_FREE_RECEIPT_SLOT: 'main',
          WORKERS_AI_ACCOUNT_ID: 'a'.repeat(32),
        },
        d1Databases: { DB: 'receipt-slots' },
        cf: false,
        host: '127.0.0.1',
        port: 0,
        inspectorPort: 0,
        outboundService: () => {
          externalRequests++;
          return new Response('denied', { status: 503 });
        },
      }),
    );
    const db = await runtime.getD1Database('DB');
    // D1 exec's line parser cannot split multi-line triggers; a prepared single statement can.
    for (const name of ['0020_free_account_receipts.sql', '0022_free_receipt_slots.sql']) {
      const sql = await readFile(new URL('apps/api/migrations/' + name, root), 'utf8');
      const statements = sql
        .replace(/--[^\n]*/g, '')
        .match(/CREATE TRIGGER[\s\S]*?END;|CREATE TABLE[\s\S]*?;/g);
      for (const statement of statements) await db.prepare(statement).run();
    }
    await db
      .prepare('CREATE TABLE dispatch_records(id INTEGER PRIMARY KEY,dispatched INTEGER NOT NULL)')
      .run();
    await db.prepare('INSERT INTO dispatch_records VALUES(1,0)').run();
    const account = 'a'.repeat(32);
    for (const id of ['A', 'B', 'C']) {
      const receipt = {
        schemaVersion: 1,
        policyVersion: 'workers-ai-free-hard-stop.v1',
        accountId: account,
        verifiedAt: new Date(Date.now() - 60000).toISOString(),
        expiresAt: new Date(Date.now() + 3600000).toISOString(),
        evidenceRef: 'synthetic-runtime-only-' + id,
        accountPlan: 'free',
        providerRoute: 'direct-workers-binding',
        gatewayCredits: false,
        paidModels: false,
        fallbacks: false,
      };
      await db
        .prepare('INSERT INTO ai_free_account_receipts VALUES(?,?,?,1,NULL)')
        .bind(id, account, JSON.stringify(receipt))
        .run();
    }
    await db
      .prepare('INSERT INTO ai_free_receipt_slots VALUES(?,?,?,1,1)')
      .bind('main', account, 'A')
      .run();
    const request = async (path) => {
      const response = await runtime.dispatchFetch('http://localhost/' + path);
      assert.equal(
        response.status,
        200,
        response.status === 200 ? undefined : await response.text(),
      );
      return response.json();
    };
    assert.deepEqual(await request('capture'), { generation: 1 });
    assert.deepEqual(await request('dispatch'), { dispatched: true });
    await db.prepare('UPDATE dispatch_records SET dispatched=0 WHERE id=1').run();
    const rotations = await Promise.all(
      ['B', 'C'].map((id) =>
        db
          .prepare(
            'UPDATE ai_free_receipt_slots SET receipt_id=?,generation=2,updated_at=2 WHERE slot_id=? AND account_id=? AND generation=1 AND receipt_id=? RETURNING receipt_id',
          )
          .bind(id, 'main', account, 'A')
          .all(),
      ),
    );
    assert.equal(
      rotations.reduce((n, result) => n + result.results.length, 0),
      1,
    );
    assert.deepEqual(await request('dispatch'), { dispatched: false });
    assert.deepEqual(await request('capture'), { generation: 2 });
    const current = await db.prepare('SELECT receipt_id FROM ai_free_receipt_slots').first();
    await db
      .prepare('UPDATE ai_free_account_receipts SET revoked_at=1 WHERE id=?')
      .bind(current.receipt_id)
      .run();
    assert.deepEqual(await request('dispatch'), { dispatched: false });
    assert.equal(
      (await db.prepare('SELECT COUNT(*) AS n FROM ai_free_receipt_slot_history').first()).n,
      2,
    );
    assert.equal(externalRequests, 0);
  },
);
