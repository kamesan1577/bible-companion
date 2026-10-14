import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readdirSync, readFileSync } from 'node:fs';
const account = 'a'.repeat(32),
  other = 'b'.repeat(32);
function fixture(t, recursive = false) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec(`PRAGMA foreign_keys=OFF;PRAGMA recursive_triggers=${recursive ? 'ON' : 'OFF'};`);
  for (const file of readdirSync(new URL('../apps/api/migrations/', import.meta.url))
    .filter((x) => x.endsWith('.sql'))
    .sort())
    db.exec(readFileSync(new URL('../apps/api/migrations/' + file, import.meta.url), 'utf8'));
  const receipt = (id, acct = account, patch = {}) => {
    const value = {
      schemaVersion: 1,
      policyVersion: 'workers-ai-free-hard-stop-v1',
      accountId: acct,
      verifiedAt: new Date(Date.now() - 60000).toISOString(),
      expiresAt: new Date(Date.now() + 3600000).toISOString(),
      evidenceRef: 'synthetic-test-not-provider-verification',
      accountPlan: 'free',
      providerRoute: 'direct-workers-binding',
      gatewayCredits: false,
      paidModels: false,
      fallbacks: false,
      ...patch,
    };
    db.prepare(
      'INSERT INTO ai_free_account_receipts(id,account_id,receipt_json,created_at) VALUES(?,?,?,1)',
    ).run(id, acct, JSON.stringify(value));
    return value;
  };
  const insert = (id = 'A', generation = 1, acct = account) =>
    db
      .prepare('INSERT INTO ai_free_receipt_slots VALUES(?,?,?,?,1)')
      .run('slot', acct, id, generation);
  const rotate = (id, generation) =>
    db
      .prepare(
        'UPDATE ai_free_receipt_slots SET receipt_id=?,generation=?,updated_at=updated_at+1 WHERE slot_id=? AND account_id=?',
      )
      .run(id, generation, 'slot', account);
  for (const id of ['A', 'B', 'C']) receipt(id);
  return { db, receipt, insert, rotate };
}
for (const recursive of [false, true])
  test(`independent review: replace cannot reset lineage or erase immutable evidence (recursive triggers ${recursive})`, (t) => {
    const { db, insert, rotate } = fixture(t, recursive);
    insert();
    rotate('B', 2);
    const before = db
      .prepare('SELECT * FROM ai_free_receipt_slot_history ORDER BY generation')
      .all();
    assert.throws(() =>
      db
        .prepare('INSERT OR REPLACE INTO ai_free_receipt_slots VALUES(?,?,?,1,3)')
        .run('slot', account, 'C'),
    );
    assert.throws(() =>
      db
        .prepare('INSERT OR REPLACE INTO ai_free_receipt_slot_history VALUES(?,?,?,1)')
        .run('slot', account, 'C'),
    );
    assert.throws(() =>
      db
        .prepare(
          'INSERT OR REPLACE INTO ai_free_account_receipts SELECT id,account_id,receipt_json,created_at,NULL FROM ai_free_account_receipts WHERE id=?',
        )
        .run('A'),
    );
    assert.deepEqual(
      db.prepare('SELECT * FROM ai_free_receipt_slot_history ORDER BY generation').all(),
      before,
    );
    assert.equal(db.prepare('SELECT generation FROM ai_free_receipt_slots').get().generation, 2);
  });
test('independent review: pointer generation, account and anti-ABA guards do not depend on foreign keys', (t) => {
  const { db, receipt, insert, rotate } = fixture(t);
  receipt('foreign', other);
  receipt('mismatch', account, { accountId: other });
  for (const [id, generation, acct] of [
    ['A', 2, account],
    ['missing', 1, account],
    ['foreign', 1, account],
    ['mismatch', 1, account],
    ['A', 1, other],
  ])
    assert.throws(() => insert(id, generation, acct));
  insert();
  for (const generation of [0, 1, 3, 1.5, 9007199254740992])
    assert.throws(() => rotate('B', generation));
  rotate('B', 2);
  assert.throws(() => rotate('A', 3));
  assert.throws(() => rotate('B', 3));
  rotate('C', 3);
  assert.throws(() => db.exec('DELETE FROM ai_free_receipt_slots'));
  assert.throws(() => db.exec('DELETE FROM ai_free_receipt_slot_history'));
  assert.throws(() => db.exec('UPDATE ai_free_receipt_slot_history SET generation=generation+100'));
  assert.throws(() =>
    db.prepare('UPDATE ai_free_receipt_slots SET account_id=?,generation=4').run(other),
  );
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM ai_free_receipt_slot_history').get().n, 3);
});
test('independent review: stale competing CAS changes neither pointer nor append-only lineage', (t) => {
  const { db, insert } = fixture(t);
  insert();
  const cas = db.prepare(
    'UPDATE ai_free_receipt_slots SET receipt_id=?,generation=2,updated_at=2 WHERE slot_id=? AND account_id=? AND generation=1 AND receipt_id=? RETURNING generation',
  );
  assert.equal(cas.get('B', 'slot', account, 'A').generation, 2);
  assert.equal(cas.get('C', 'slot', account, 'A'), undefined);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM ai_free_receipt_slot_history').get().n, 2);
});
test('independent review: activation rejects expired, future, overlong and revoked evidence', (t) => {
  const { db, receipt, insert } = fixture(t);
  receipt('expired', account, {
    verifiedAt: new Date(Date.now() - 3600000).toISOString(),
    expiresAt: new Date(Date.now() - 1000).toISOString(),
  });
  receipt('future', account, { verifiedAt: new Date(Date.now() + 60000).toISOString() });
  receipt('long', account, { expiresAt: new Date(Date.now() + 86400000).toISOString() });
  receipt('invalid', account, { expiresAt: 'not-a-date' });
  receipt('revoked');
  db.exec("UPDATE ai_free_account_receipts SET revoked_at=1 WHERE id='revoked'");
  for (const id of ['expired', 'future', 'long', 'invalid', 'revoked'])
    assert.throws(() => insert(id));
});

import {
  profileTemplate,
  validateOperatorProfile,
  profileToConfig,
  receiptSql,
  receiptSlotSql,
  verifyReceiptSlotResult,
  digest,
  runOperator,
  writeExclusive,
  ROOT,
  CONFIG_PATH,
} from './operator.mjs';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
function activeProfile() {
  const p = {
    ...profileTemplate(),
    accountId: account,
    databaseId: '11111111-2222-3333-4444-555555555555',
    origin: 'https://review.example.com',
    rpId: 'review.example.com',
  };
  p.modelIds = [p.defaultModelId];
  p.freeReceiptSlot = { id: 'slot', expectedGeneration: 0, expectedReceiptId: null };
  p.freeReceipt = {
    id: 'operator-A',
    receipt: {
      schemaVersion: 1,
      policyVersion: 'workers-ai-free-hard-stop.v1',
      accountId: account,
      verifiedAt: new Date(Date.now() - 60000).toISOString(),
      expiresAt: new Date(Date.now() + 3600000).toISOString(),
      evidenceRef: 'sha256:' + 'c'.repeat(64),
      accountPlan: 'free',
      providerRoute: 'direct-workers-binding',
      gatewayCredits: false,
      paidModels: false,
      fallbacks: false,
    },
  };
  Object.assign(p.termsReviews[0], {
    status: 'reviewed',
    evidenceRef: 'sha256:' + 'd'.repeat(64),
    reviewedAt: new Date(Date.now() - 60000).toISOString(),
  });
  return validateOperatorProfile(p);
}
const wrapped = (rows) => [{ success: true, results: rows }];
test('independent review: install never activates; explicit slot CAS requires exact evidence and readback; replay does not reapply', (t) => {
  const { db } = fixture(t),
    p = activeProfile(),
    first = receiptSlotSql(p);
  assert.deepEqual(db.prepare(first.sql).all(), []);
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM ai_free_receipt_slots').get().n, 0);
  db.exec(receiptSql(p));
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM ai_free_receipt_slots').get().n, 0);
  assert(verifyReceiptSlotResult(wrapped(db.prepare(first.sql).all()), first.identity));
  assert(verifyReceiptSlotResult(wrapped(db.prepare(first.readbackSql).all()), first.identity));
  assert(!verifyReceiptSlotResult(wrapped(db.prepare(first.sql).all()), first.identity));
  const p2 = validateOperatorProfile({
      ...p,
      freeReceiptSlot: { id: 'slot', expectedGeneration: 1, expectedReceiptId: p.freeReceipt.id },
      freeReceipt: { ...p.freeReceipt, id: 'operator-B' },
    }),
    next = receiptSlotSql(p2);
  assert.deepEqual(profileToConfig(p), profileToConfig(p2));
  assert.notEqual(digest(p), digest(p2));
  assert.deepEqual(db.prepare(next.sql).all(), []);
  db.exec(receiptSql(p2));
  assert(verifyReceiptSlotResult(wrapped(db.prepare(next.sql).all()), next.identity));
  assert(!verifyReceiptSlotResult(wrapped(db.prepare(next.sql).all()), next.identity));
  assert(!verifyReceiptSlotResult(wrapped(db.prepare(first.readbackSql).all()), first.identity));
  for (const rows of [
    [],
    [{ success: false, results: [next.identity] }],
    [{ success: true, results: [next.identity, next.identity] }],
    [...wrapped([next.identity]), ...wrapped([next.identity])],
    wrapped([{ ...next.identity, account_id: other }]),
    wrapped([{ ...next.identity, generation: 1 }]),
  ])
    assert(!verifyReceiptSlotResult(rows, next.identity));
});
test('independent review: immutable installation replay preserves revoked evidence and current pointer', (t) => {
  const { db } = fixture(t),
    p = activeProfile();
  db.exec(receiptSql(p));
  db.exec(receiptSlotSql(p).sql);
  db.exec("UPDATE ai_free_account_receipts SET revoked_at=1 WHERE id='operator-A'");
  const before = db.prepare('SELECT total_changes() AS n').get().n;
  db.exec(receiptSql(p));
  assert.equal(db.prepare('SELECT total_changes() AS n').get().n, before);
  assert.equal(
    db.prepare("SELECT revoked_at FROM ai_free_account_receipts WHERE id='operator-A'").get()
      .revoked_at,
    1,
  );
  const rotation = receiptSlotSql(p);
  assert(
    !verifyReceiptSlotResult(wrapped(db.prepare(rotation.readbackSql).all()), rotation.identity),
  );
});
function operatorFixture(t) {
  const root = mkdtempSync(resolve(tmpdir(), 'receipt-review-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(resolve(root, 'apps/api'), { recursive: true });
  writeFileSync(
    resolve(root, 'apps/api/wrangler.jsonc'),
    readFileSync(resolve(ROOT, 'apps/api/wrangler.jsonc')),
  );
  const p = activeProfile(),
    path = '.cache/operator/profile.json',
    calls = [],
    now = Date.now();
  writeExclusive(root, path, JSON.stringify(p));
  const opts = {
    root,
    clock: () => now,
    output() {},
    run(exe, args, options) {
      calls.push({ exe, args, options });
      if (args.includes('whoami'))
        return JSON.stringify({ loggedIn: true, accounts: [{ id: p.accountId }] });
      if (args.includes('info')) return JSON.stringify({ uuid: p.databaseId });
      const identity = receiptSlotSql(p, now).identity;
      return JSON.stringify(wrapped([identity]));
    },
  };
  runOperator(['prepare', '--profile', path], opts);
  const action = 'rotate-receipt-slot',
    args = [
      'apply',
      '--profile',
      path,
      '--action',
      action,
      '--execute',
      '--allow-remote',
      '--confirm',
      `${action}:${p.accountId}:${p.databaseId}:${digest(p)}`,
    ];
  return { root, p, path, calls, opts, args };
}
test('independent review: slot action authorization binds action, account, database and entire profile before subprocess', (t) => {
  const f = operatorFixture(t);
  for (const field of ['action', 'account', 'database', 'profile']) {
    const bad = [...f.args];
    bad[bad.length - 1] =
      field === 'action'
        ? bad.at(-1).replace('rotate-receipt-slot', 'install-receipt')
        : field === 'account'
          ? bad.at(-1).replace(account, other)
          : field === 'database'
            ? bad.at(-1).replace(f.p.databaseId, '00000000-0000-0000-0000-000000000000')
            : bad.at(-1).slice(0, -1) + 'x';
    assert.throws(() => runOperator(bad, f.opts));
  }
  assert.equal(f.calls.length, 0);
  runOperator(f.args, f.opts);
  assert.equal(f.calls.length, 4);
  assert(f.calls[0].args.includes('whoami'));
  assert(f.calls[1].args.includes('info'));
  assert(f.calls[2].args.some((x) => x.startsWith('INSERT INTO ai_free_receipt_slots')));
  assert(f.calls[3].args.some((x) => x.startsWith('SELECT ')));
  assert(f.calls.every((c) => c.options.env.CLOUDFLARE_ACCOUNT_ID === account));
});
test('independent review: wrong provider identity or prepared config cannot reach slot mutation', (t) => {
  for (const wrong of ['account', 'database', 'config']) {
    const f = operatorFixture(t),
      run = f.opts.run;
    if (wrong === 'config') writeFileSync(resolve(f.root, CONFIG_PATH), '{}');
    else
      f.opts.run = (exe, args, opts) => {
        const result = run(exe, args, opts);
        return wrong === 'account' && args.includes('whoami')
          ? JSON.stringify({ loggedIn: true, accounts: [{ id: other }] })
          : wrong === 'database' && args.includes('info')
            ? JSON.stringify({ uuid: 'wrong' })
            : result;
      };
    assert.throws(() => runOperator(f.args, f.opts));
    assert(f.calls.length <= 2);
  }
});
test('independent review: uncertain mutation acknowledgement stops before readback/retry or any unrelated action', (t) => {
  const f = operatorFixture(t),
    run = f.opts.run;
  f.opts.run = (exe, args, opts) => {
    const result = run(exe, args, opts);
    if (args.some((x) => x.startsWith('INSERT INTO ai_free_receipt_slots')))
      throw Error('synthetic lost acknowledgement after possible commit');
    return result;
  };
  assert.throws(() => runOperator(f.args, f.opts));
  assert.equal(f.calls.length, 3);
  assert(!f.calls.some((c) => c.args[1] === 'deploy'));
});
