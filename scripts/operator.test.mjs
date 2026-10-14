import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  readFileSync,
  rmSync,
  symlinkSync,
  statSync,
  existsSync,
  readdirSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import {
  profileTemplate,
  preparePinnedAssets,
  validateOperatorProfile,
  profileToConfig,
  operatorPlan,
  digest,
  safePath,
  readJson,
  writeExclusive,
  receiptSql,
  inviteSql,
  runOperator,
  ROOT,
  CONFIG_PATH,
} from './operator.mjs';
const NOW = Date.parse('2026-10-13T19:00:00Z');
const ACCOUNT = 'a'.repeat(32),
  DB = '11111111-2222-3333-4444-555555555555';
function profile(active = false) {
  const p = {
    ...profileTemplate(),
    accountId: ACCOUNT,
    databaseId: DB,
    origin: 'https://bible.example.com',
    rpId: 'bible.example.com',
  };
  if (active) {
    p.modelIds = [p.defaultModelId];
    p.freeReceipt = {
      id: 'operator-test-fixture-never-live',
      receipt: {
        schemaVersion: 1,
        policyVersion: 'workers-ai-free-hard-stop.v1',
        accountId: ACCOUNT,
        verifiedAt: '2026-10-13T18:00:00Z',
        expiresAt: '2026-10-14T18:00:00Z',
        evidenceRef: 'sha256:' + 'b'.repeat(64),
        accountPlan: 'free',
        providerRoute: 'direct-workers-binding',
        gatewayCredits: false,
        paidModels: false,
        fallbacks: false,
      },
    };
    Object.assign(p.termsReviews[0], {
      status: 'reviewed',
      evidenceRef: 'sha256:' + 'c'.repeat(64),
      reviewedAt: '2026-10-13T18:00:00Z',
    });
  }
  return p;
}
function setup(t, active = false) {
  const root = mkdtempSync(resolve(tmpdir(), 'operator-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(resolve(root, 'apps/api'), { recursive: true });
  writeFileSync(
    resolve(root, 'apps/api/wrangler.jsonc'),
    readFileSync(resolve(ROOT, 'apps/api/wrangler.jsonc')),
  );
  const p = profile(active),
    path = '.cache/operator/profile.json';
  writeExclusive(root, path, JSON.stringify(p));
  const calls = [],
    messages = [];
  const run = (exe, args, opts) => {
    calls.push({ exe, args, opts });
    if (args.includes('whoami'))
      return JSON.stringify({ loggedIn: true, accounts: [{ id: ACCOUNT }] });
    if (args.includes('info')) return JSON.stringify({ uuid: DB });
    return '[]';
  };
  const opts = { root, clock: () => NOW, run, output: (x) => messages.push(x) };
  return { root, p, path, calls, messages, opts };
}
function applyArgs(p, path, action = 'deploy') {
  return [
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
}
test('template is a genuinely pending 22-model ledger and cannot activate', () => {
  const p = profileTemplate();
  assert.equal(p.termsReviews.length, 22);
  assert.equal(new Set(p.termsReviews.map((r) => r.modelId)).size, 22);
  assert(
    p.termsReviews.every(
      (r) => r.status === 'pending' && r.evidenceRef === null && r.reviewedAt === null,
    ),
  );
  assert.deepEqual(p.modelIds, []);
  assert.equal(p.freeReceipt, null);
  assert.throws(() => validateOperatorProfile(p, NOW));
});
test('disconnected and active profiles map to strict no-cost config', () => {
  const c = profileToConfig(profile(), NOW);
  assert.equal(c.vars.AI_ENABLED, 'false');
  assert.equal(c.ai, undefined);
  assert.equal(c.preview_urls, false);
  assert.deepEqual(c.limits, { cpu_ms: 10 });
  const a = profileToConfig(profile(true), NOW);
  assert.deepEqual(a.ai, { binding: 'AI' });
  assert.equal(a.vars.WORKERS_AI_ACCOUNT_ID, ACCOUNT);
  assert.equal(a.vars.AI_BUDGET_MODE, 'free-provider-hard-stop');
  assert.deepEqual(a.routes, [{ pattern: 'bible.example.com', custom_domain: true }]);
  assert(!JSON.stringify(a).includes('API_TOKEN'));
});
for (const [label, mutate] of [
  ['unknown model', (p) => (p.modelIds = ['@unknown/provider'])],
  [
    'paid model',
    (p) => {
      p.modelIds = ['@cf/moonshotai/kimi-k2.6'];
      p.defaultModelId = p.modelIds[0];
    },
  ],
  ['paid account', (p) => (p.freeReceipt.receipt.accountPlan = 'paid')],
  ['paid fallback', (p) => (p.freeReceipt.receipt.fallbacks = true)],
  ['gateway routing', (p) => (p.freeReceipt.receipt.providerRoute = 'ai-gateway')],
  ['prepaid credits', (p) => (p.freeReceipt.receipt.gatewayCredits = true)],
  ['account mismatch', (p) => (p.freeReceipt.receipt.accountId = 'd'.repeat(32))],
  ['expired receipt', (p) => (p.freeReceipt.receipt.expiresAt = '2026-10-13T18:30:00Z')],
  ['future receipt', (p) => (p.freeReceipt.receipt.verifiedAt = '2026-10-13T19:01:00Z')],
  ['long receipt', (p) => (p.freeReceipt.receipt.expiresAt = '2026-10-14T18:00:01Z')],
  ['unreviewed terms', (p) => (p.termsReviews[0].status = 'pending')],
  ['fabricated review without evidence', (p) => (p.termsReviews[0].evidenceRef = null)],
  ['duplicate review', (p) => (p.termsReviews[1] = p.termsReviews[0])],
  ['secret injection', (p) => (p.apiKey = 'never-print-secret')],
  [
    'secret URL',
    (p) => (p.termsReviews[0].termsUrls = ['https://www.cloudflare.com/?token=never-print-secret']),
  ],
  ['receipt injection', (p) => (p.freeReceipt.receipt.evidenceRef = "'); DROP TABLE users; --")],
  ['silent experimental mode', (p) => p.answerModes.push('grounded-generation')],
  ['unstable origin', (p) => (p.origin = 'http://bible.example.com')],
  ['RP mismatch', (p) => (p.rpId = 'evil.example.com')],
])
  test(`rejects ${label}`, () => {
    const p = profile(true);
    mutate(p);
    assert.throws(() => validateOperatorProfile(p, NOW));
  });
test('experimental mode is explicit and disclosures never claim semantic proof', () => {
  const p = profile(true);
  p.answerModes.push('grounded-generation');
  p.experimentalGroundedReviewed = true;
  p.defaultAnswerMode = 'grounded-generation';
  const plan = operatorPlan(p, NOW);
  assert.match(plan.experimentalDisclosure, /do not establish semantic truth/);
  assert.match(plan.estimateDisclosure, /estimates, not hard token bounds/);
  assert.equal(plan.paidFallback, false);
});
test('template, plan, validate and prepare never invoke process runner', (t) => {
  const { p, path, opts, calls, root, messages } = setup(t, true);
  for (const command of ['plan', 'validate', 'prepare'])
    runOperator([command, '--profile', path], opts);
  assert.equal(calls.length, 0);
  assert.equal(statSync(resolve(root, CONFIG_PATH)).mode & 0o777, 0o600);
  assert.equal(
    readFileSync(resolve(root, CONFIG_PATH), 'utf8'),
    JSON.stringify(profileToConfig(p, NOW, root), null, 2) + '\n',
  );
  assert.throws(() => runOperator(['prepare', '--profile', path], opts));
  assert(!messages.join().includes('b'.repeat(64)));
});
test('rejects traversal, absolute paths, dot paths, symlinks and overwrites', (t) => {
  const { root } = setup(t);
  for (const path of [
    '/tmp/profile.json',
    '.cache/operator/../escape.json',
    '.cache/operator/a/../../escape.json',
    '.cache/operator/./x.json',
    '.cache/operator/a;touch.json',
  ])
    assert.throws(() => safePath(root, path));
  writeExclusive(root, '.cache/operator/safe.json', '{}');
  assert.throws(() => writeExclusive(root, '.cache/operator/safe.json', 'overwritten'));
  symlinkSync(
    resolve(root, '.cache/operator/safe.json'),
    resolve(root, '.cache/operator/link.json'),
  );
  assert.throws(() => readJson(root, '.cache/operator/link.json'));
  mkdirSync(resolve(root, 'outside'));
  symlinkSync(resolve(root, 'outside'), resolve(root, '.cache/operator/linkdir'));
  assert.throws(() => writeExclusive(root, '.cache/operator/linkdir/new.json', '{}'));
  assert(!existsSync(resolve(root, 'outside/new.json')));
});
test('rejects symlinked operator config and root ancestors', (t) => {
  const { root, path, opts } = setup(t);
  symlinkSync(resolve(root, 'apps/api/wrangler.jsonc'), resolve(root, CONFIG_PATH));
  assert.throws(() => runOperator(['prepare', '--profile', path], opts));
  const alias = root + '-alias';
  symlinkSync(root, alias);
  t.after(() => rmSync(alias));
  assert.throws(() => readJson(alias, path));
});
test('all remote gates precede any subprocess and exact profile fingerprint is required', (t) => {
  const { p, path, opts, calls } = setup(t);
  for (const args of [
    ['apply', '--profile', path, '--action', 'deploy'],
    applyArgs(p, path).filter((a) => a !== '--allow-remote'),
    applyArgs(p, path).map((a) =>
      a === `deploy:${ACCOUNT}:${DB}:${digest(p)}` ? 'deploy:wrong' : a,
    ),
  ])
    assert.throws(() => runOperator(args, opts));
  assert.equal(calls.length, 0);
});
test('unknown/duplicate flags and alternate config/command cannot smuggle execution', (t) => {
  const { path, opts, calls } = setup(t);
  for (const args of [
    ['prepare', '--profile', path, '--execute'],
    ['plan', '--profile', path, '--profile', path],
    ['apply', '--profile', path, '--config', '/tmp/evil'],
    ['rm', '--execute'],
  ])
    assert.throws(() => runOperator(args, opts));
  assert.equal(calls.length, 0);
});
test('future authorized deploy verifies auth and D1 before one mutation, entirely mocked', (t) => {
  const { p, path, opts, calls } = setup(t);
  runOperator(['prepare', '--profile', path], opts);
  runOperator(applyArgs(p, path), opts);
  assert.equal(calls.length, 3);
  assert(calls[0].args.includes('whoami'));
  assert(calls[1].args.includes('info'));
  assert.equal(calls[2].args[1], 'deploy');
  assert.equal(calls[2].opts.env.CLOUDFLARE_ACCOUNT_ID, ACCOUNT);
});
test('wrong account or D1 and changed config stop before mutation', (t) => {
  for (const wrong of ['account', 'db', 'config']) {
    const { p, path, root, opts, calls } = setup(t);
    runOperator(['prepare', '--profile', path], opts);
    if (wrong === 'config') writeFileSync(resolve(root, CONFIG_PATH), '{}');
    const run = opts.run;
    opts.run = (exe, args, o) => {
      const normal = run(exe, args, o);
      return wrong === 'account' && args.includes('whoami')
        ? '{}'
        : wrong === 'db' && args.includes('info')
          ? '{"uuid":"wrong"}'
          : normal;
    };
    assert.throws(() => runOperator(applyArgs(p, path), opts));
    assert(calls.length <= 2);
  }
});
test('receipt expiry during preflight stops mutation', (t) => {
  const { p, path, opts, calls } = setup(t, true);
  runOperator(['prepare', '--profile', path], opts);
  let reads = 0;
  opts.clock = () => (++reads === 1 ? NOW : Date.parse(p.freeReceipt.receipt.expiresAt));
  assert.throws(() => runOperator(applyArgs(p, path, 'install-receipt'), opts));
  assert.equal(calls.length, 2);
});
test('receipt SQL cannot replace or reactivate immutable evidence', () => {
  const sql = receiptSql(profile(true));
  assert.match(sql, /^INSERT INTO ai_free_account_receipts/);
  assert(!/REPLACE|UPDATE|DELETE|revoked_at/.test(sql));
});
test('owner invite uses atomic existing owner and pending owner exclusion and one-hour expiry', () => {
  const sql = inviteSql('owner', 'a'.repeat(43), 1000 + 3600, 1000);
  assert.match(sql, /NOT EXISTS\(SELECT 1 FROM users/);
  assert.match(sql, /NOT EXISTS\(SELECT 1 FROM invitations/);
  assert.match(sql, /RETURNING token_hash/);
  assert.throws(() => inviteSql('owner', 'a'.repeat(43), 4601, 1000));
  assert.throws(() => inviteSql("owner';DROP", 'a'.repeat(43), 1100, 1000));
});
test('invitation only prints token after provider confirms hashed insert, mocked', (t) => {
  const { p, path, opts, calls, messages } = setup(t);
  runOperator(['prepare', '--profile', path], opts);
  const run = opts.run;
  opts.run = (exe, args, o) => {
    const result = run(exe, args, o);
    if (args.includes('execute')) {
      const sql = args[args.indexOf('--command') + 1],
        hash = sql.match(/SELECT '([^']+)'/)[1];
      return JSON.stringify([{ success: true, results: [{ token_hash: hash }] }]);
    }
    return result;
  };
  opts.random = () => Buffer.alloc(32, 9);
  runOperator(applyArgs(p, path, 'invite-owner'), opts);
  const token = Buffer.alloc(32, 9).toString('base64url');
  assert(messages.at(-1).includes(token));
  assert(!JSON.stringify(calls).includes(token));
});
test('existing owner does not print a nonexistent invite', (t) => {
  const { p, path, opts, messages } = setup(t);
  runOperator(['prepare', '--profile', path], opts);
  assert.throws(() => runOperator(applyArgs(p, path, 'invite-owner'), opts));
  assert.equal(messages.length, 1);
});
test('GitHub plan is local and explicit private creation has no push', (t) => {
  const { opts, calls } = setup(t);
  runOperator(['github-plan', '--owner', 'owner'], opts);
  assert.equal(calls.length, 0);
  opts.run = (exe, args) => {
    calls.push({ exe, args });
    if (args[0] === 'api') return '{"login":"owner","type":"User"}';
    if (args[1] === 'view')
      return '{"visibility":"PRIVATE","nameWithOwner":"owner/bible-companion","url":"https://github.com/owner/bible-companion"}';
    return '';
  };
  runOperator(
    [
      'github-apply',
      '--owner',
      'owner',
      '--action',
      'create',
      '--execute',
      '--allow-remote',
      '--confirm',
      'create:owner/bible-companion:private',
    ],
    opts,
  );
  assert(calls.some((c) => c.args.includes('--private')));
  assert(!calls.some((c) => c.exe === 'git'));
});
test('GitHub wrong owner/public visibility/wrong remote prevent push', (t) => {
  for (const fail of ['owner', 'public', 'remote']) {
    const { opts, calls } = setup(t);
    opts.run = (exe, args) => {
      calls.push({ exe, args });
      if (args[0] === 'api')
        return JSON.stringify({ login: fail === 'owner' ? 'other' : 'owner', type: 'User' });
      if (args[1] === 'view')
        return JSON.stringify({
          visibility: fail === 'public' ? 'PUBLIC' : 'PRIVATE',
          nameWithOwner: 'owner/bible-companion',
          url: 'https://github.com/owner/bible-companion',
        });
      if (args[0] === 'remote') return 'https://github.com/other/public.git';
      return '';
    };
    assert.throws(() =>
      runOperator(
        [
          'github-apply',
          '--owner',
          'owner',
          '--action',
          'push',
          '--execute',
          '--allow-remote',
          '--confirm',
          'push:owner/bible-companion:private',
        ],
        opts,
      ),
    );
    assert(!calls.some((c) => c.args[0] === 'push'));
  }
});
test('receipt retry accepts only exact active bytes and rejects conflict/revocation, mocked', (t) => {
  for (const state of ['active', 'different', 'revoked']) {
    const { p, path, opts, calls } = setup(t, true);
    runOperator(['prepare', '--profile', path], opts);
    const run = opts.run;
    opts.run = (exe, args, o) => {
      const result = run(exe, args, o);
      const sql = args[args.indexOf('--command') + 1] ?? '';
      if (sql.startsWith('SELECT account_id'))
        return JSON.stringify([
          {
            success: true,
            results: [
              {
                account_id: ACCOUNT,
                receipt_json: state === 'different' ? '{}' : JSON.stringify(p.freeReceipt.receipt),
                revoked_at: state === 'revoked' ? 1 : null,
              },
            ],
          },
        ]);
      return result;
    };
    if (state === 'active') runOperator(applyArgs(p, path, 'install-receipt'), opts);
    else assert.throws(() => runOperator(applyArgs(p, path, 'install-receipt'), opts));
    assert(
      calls.some((c) =>
        c.args.some((a) =>
          a.includes('WHERE NOT EXISTS(SELECT 1 FROM ai_free_account_receipts WHERE id='),
        ),
      ),
    );
    assert(!calls.some((c) => c.args.some((a) => a.includes('UPDATE ai_free_account_receipts'))));
  }
});
test('expired receipt can still be planned and revoked, with exact account and ID', (t) => {
  const { p, path, opts, calls, messages } = setup(t, true);
  runOperator(['prepare', '--profile', path], opts);
  opts.clock = () => Date.parse(p.freeReceipt.receipt.expiresAt) + 1;
  runOperator(['plan', '--profile', path], opts);
  const plan = JSON.parse(messages.at(-1));
  assert.equal(plan.receiptCurrent, false);
  assert.equal(plan.receiptMaintenance.expiresAt, p.freeReceipt.receipt.expiresAt);
  assert.equal(plan.receiptMaintenance.automaticRenewal, false);
  assert.equal(plan.receiptMaintenance.deploymentRequiredForNewId, true);
  assert.match(plan.receiptMaintenance.guidance, /Installation alone does not change/);
  assert.throws(
    () => runOperator(['validate', '--profile', path], opts),
    /receipt expired.*install-receipt and deploy/,
  );
  assert.equal(calls.length, 0);
  const run = opts.run;
  opts.run = (exe, args, o) => {
    const result = run(exe, args, o);
    const sql = args[args.indexOf('--command') + 1] ?? '';
    if (sql.startsWith('UPDATE ai_free_account_receipts'))
      return JSON.stringify([{ success: true, results: [{ id: p.freeReceipt.id }] }]);
    return result;
  };
  runOperator(applyArgs(p, path, 'revoke-receipt'), opts);
  const update = calls.at(-1).args.join(' ');
  assert(update.includes(`account_id='${ACCOUNT}'`));
  assert(update.includes(`id='${p.freeReceipt.id}'`));
  assert(update.includes('COALESCE(revoked_at,'));
});
test('successful private push verifies exact remote first, mocked', (t) => {
  const { opts, calls } = setup(t);
  opts.run = (exe, args) => {
    calls.push({ exe, args });
    if (args[0] === 'api') return '{"login":"owner","type":"User"}';
    if (args[1] === 'view')
      return '{"visibility":"PRIVATE","nameWithOwner":"owner/bible-companion","url":"https://github.com/owner/bible-companion"}';
    if (args[0] === 'remote') return 'git@github.com:owner/bible-companion.git';
    return '';
  };
  runOperator(
    [
      'github-apply',
      '--owner',
      'owner',
      '--action',
      'push',
      '--execute',
      '--allow-remote',
      '--confirm',
      'push:owner/bible-companion:private',
    ],
    opts,
  );
  assert.deepEqual(calls.at(-1), {
    exe: 'git',
    args: ['push', 'git@github.com:owner/bible-companion.git', 'HEAD:refs/heads/main'],
  });
  assert.equal(calls.at(-3).args[0], 'remote');
  assert.deepEqual(calls.at(-2).args, ['config', '--name-only', '--list']);
});
test('multiple Git push URLs cannot hide a second destination', (t) => {
  const { opts, calls } = setup(t);
  opts.run = (exe, args) => {
    calls.push({ exe, args });
    if (args[0] === 'api') return '{"login":"owner","type":"User"}';
    if (args[1] === 'view')
      return '{"visibility":"PRIVATE","nameWithOwner":"owner/bible-companion","url":"https://github.com/owner/bible-companion"}';
    if (args[0] === 'remote') {
      assert(args.includes('--all'));
      return 'git@github.com:owner/bible-companion.git\ngit@github.com:other/public.git\n';
    }
    return '';
  };
  assert.throws(() =>
    runOperator(
      [
        'github-apply',
        '--owner',
        'owner',
        '--action',
        'push',
        '--execute',
        '--allow-remote',
        '--confirm',
        'push:owner/bible-companion:private',
      ],
      opts,
    ),
  );
  assert(!calls.some((c) => c.args[0] === 'push'));
});
test('oversized operator input is rejected before parsing', (t) => {
  const { root } = setup(t);
  const path = '.cache/operator/oversized.json';
  writeExclusive(root, path, ' '.repeat(128 * 1024 + 1));
  assert.throws(() => readJson(root, path), /bounded regular file/);
});
test('optional pinned corpus, daily cron and reviewed allowances appear in the exact plan/config', () => {
  const p = profile();
  p.corpus = 'webp-pinned-assets';
  p.cleanup = 'daily-utc';
  p.dailyAppBudget = 9000;
  p.dailyUserBudget = 4500;
  const c = profileToConfig(p, NOW);
  assert.deepEqual(c.triggers, { crons: ['17 3 * * *'] });
  assert.equal(c.assets.binding, 'SCRIPTURE_ASSETS');
  assert.equal(c.assets.run_worker_first, true);
  assert.equal(c.vars.DAILY_USER_BUDGET, '4500');
  const plan = operatorPlan(p, NOW);
  assert.equal(plan.corpus.verseRowsWritten, 0);
  assert.equal(plan.budgets.automaticIncrease, false);
  assert(plan.steps.some((s) => s.includes('register-corpus')));
  assert.match(plan.comparisonGuidance, /reduce trial count/);
  const closed = profileToConfig(profile(), NOW);
  assert.equal(closed.assets, undefined);
  assert.equal(closed.triggers, undefined);
  for (const mutate of [
    (p) => (p.dailyAppBudget = 10001),
    (p) => (p.dailyUserBudget = 9001),
    (p) => (p.dailyAppBudget = 0),
    (p) => (p.dailyUserBudget = 1.5),
    (p) => (p.cleanup = '* * * * *'),
    (p) => (p.corpus = 'arbitrary-url'),
  ]) {
    const bad = profile();
    mutate(bad);
    assert.throws(() => validateOperatorProfile(bad, NOW));
  }
});
test('pinned corpus prepare stays local and register/deploy readback verifies real SQLite identity', (t) => {
  const x = setup(t);
  x.p.corpus = 'webp-pinned-assets';
  x.p.cleanup = 'daily-utc';
  writeFileSync(resolve(x.root, x.path), JSON.stringify(x.p));
  let builds = 0;
  x.opts.prepareAssets = () => {
    builds++;
    return { networkRequests: 0 };
  };
  runOperator(['prepare', '--profile', x.path], x.opts);
  assert.equal(builds, 1);
  assert.equal(x.calls.length, 0);
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec('PRAGMA foreign_keys=ON');
  for (const file of readdirSync(resolve(ROOT, 'apps/api/migrations'))
    .filter((n) => n.endsWith('.sql'))
    .sort())
    db.exec(readFileSync(resolve(ROOT, 'apps/api/migrations', file), 'utf8'));
  const base = x.opts.run;
  x.opts.run = (exe, args, opts) => {
    if (args.includes('execute')) {
      x.calls.push({ exe, args, opts });
      const sql = args[args.indexOf('--command') + 1];
      if (sql.startsWith('SELECT'))
        return JSON.stringify([{ success: true, results: db.prepare(sql).all() }]);
      db.exec(sql);
      return '[{"success":true,"results":[]}]';
    }
    return base(exe, args, opts);
  };
  assert.throws(() => runOperator(applyArgs(x.p, x.path, 'deploy'), x.opts), /Register the exact/);
  assert(!x.calls.some((c) => c.args.includes('deploy')));
  runOperator(applyArgs(x.p, x.path, 'register-corpus'), x.opts);
  runOperator(applyArgs(x.p, x.path, 'register-corpus'), x.opts);
  assert.equal(db.prepare('SELECT count(*) AS n FROM scripture_corpora').get().n, 1);
  assert.equal(db.prepare('SELECT count(*) AS n FROM scripture_verses').get().n, 0);
  runOperator(applyArgs(x.p, x.path, 'deploy'), x.opts);
  assert.equal(x.calls.filter((c) => c.args.includes('deploy')).length, 1);
  db.exec("UPDATE scripture_corpora SET rights_status='revoked',active=0");
  assert.throws(
    () => runOperator(applyArgs(x.p, x.path, 'register-corpus'), x.opts),
    /no reapproval/,
  );
  assert.throws(() => runOperator(applyArgs(x.p, x.path, 'deploy'), x.opts), /Register the exact/);
  assert.equal(x.calls.filter((c) => c.args.includes('deploy')).length, 1);
});
test('real offline corpus preparation refuses any extra file that an Assets uploader could publish', (t) => {
  const result = preparePinnedAssets();
  assert.equal(result.networkRequests, 0);
  assert.equal(result.verseCount, 31095);
  const extra = resolve(
    ROOT,
    '.cache/scripture/assets/operator-test-unexpected-' + process.pid + '.txt',
  );
  writeFileSync(extra, 'synthetic extra file', { flag: 'wx' });
  t.after(() => rmSync(extra, { force: true }));
  assert.throws(() => preparePinnedAssets(), /Unexpected or linked asset upload/);
});
test('Git URL rewriting cannot change an explicitly verified private push target', (t) => {
  const x = setup(t);
  x.opts.run = (exe, args) => {
    x.calls.push({ exe, args });
    if (args[0] === 'api') return '{"login":"owner","type":"User"}';
    if (args[1] === 'view')
      return '{"visibility":"PRIVATE","nameWithOwner":"owner/bible-companion","url":"https://github.com/owner/bible-companion"}';
    if (args[0] === 'remote') return 'git@github.com:owner/bible-companion.git';
    if (args[0] === 'config') return 'url.https://other.example/.pushinsteadof\n';
    return '';
  };
  assert.throws(
    () =>
      runOperator(
        [
          'github-apply',
          '--owner',
          'owner',
          '--action',
          'push',
          '--execute',
          '--allow-remote',
          '--confirm',
          'push:owner/bible-companion:private',
        ],
        x.opts,
      ),
    /URL rewriting/,
  );
  assert(!x.calls.some((c) => c.args[0] === 'push'));
});
