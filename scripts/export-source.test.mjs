import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { exportSource } from './export-source.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'bible-source-export-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const repo = join(root, 'repo');
  mkdirSync(repo);
  const git = (...args) => execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8' }).trim();
  git('init', '-q');
  git('config', 'user.name', 'Export Test');
  git('config', 'user.email', 'export-test@example.invalid');
  writeFileSync(join(repo, 'hello.txt'), 'Committed source\n');
  writeFileSync(join(repo, '.gitignore'), '.env\nnode_modules/\n');
  writeFileSync(join(repo, '.gitattributes'), 'hello.txt export-ignore\n');
  git('add', '.');
  git('commit', '-qm', 'fixture');
  return { root, repo, git, commit: git('rev-parse', 'HEAD') };
}

test('archive and manifest are byte-identical; all committed content survives attributes', (t) => {
  const { root, repo, commit } = fixture(t);
  writeFileSync(join(repo, '.env'), 'PRIVATE_RUNTIME_DATA');
  mkdirSync(join(repo, 'node_modules'));
  writeFileSync(join(repo, 'node_modules', 'secret'), 'PRIVATE_RUNTIME_DATA');
  const a = exportSource({ repo, output: join(root, 'a') });
  const b = exportSource({ repo, commit, output: join(root, 'b') });
  assert.deepEqual(a, b);
  for (const name of [a.archive, 'manifest.json']) {
    assert.deepEqual(readFileSync(join(root, 'a', name)), readFileSync(join(root, 'b', name)));
  }
  assert.equal(a.commit, commit);
  assert.deepEqual(
    a.files.map((f) => f.path),
    ['.gitattributes', '.gitignore', 'hello.txt'],
  );
  const archive = join(root, 'a', a.archive);
  assert.equal(
    execFileSync('tar', ['-xOf', archive, 'bible-companion/hello.txt'], { encoding: 'utf8' }),
    'Committed source\n',
  );
  assert.equal(readFileSync(archive).includes(Buffer.from('PRIVATE_RUNTIME_DATA')), false);
  assert.equal(
    execFileSync('tar', ['-tf', archive], { encoding: 'utf8' }).trim().split('\n').length,
    3,
  );
});

test('dirty default fails, exact commit excludes changed and untracked content', (t) => {
  const { root, repo, commit } = fixture(t);
  writeFileSync(join(repo, 'hello.txt'), 'Changed');
  writeFileSync(join(repo, 'untracked.txt'), 'Untracked');
  assert.throws(() => exportSource({ repo, output: join(root, 'a') }), /Dirty working tree/);
  const result = exportSource({ repo, commit, output: join(root, 'a') });
  assert.equal(
    execFileSync('tar', ['-xOf', join(root, 'a', result.archive), 'bible-companion/hello.txt'], {
      encoding: 'utf8',
    }),
    'Committed source\n',
  );
  assert.throws(() => exportSource({ repo, commit: 'HEAD', output: join(root, 'b') }), /object ID/);
});

test('refuses all output collisions without altering existing data', (t) => {
  const { root, repo } = fixture(t);
  const output = join(root, 'existing');
  mkdirSync(output);
  writeFileSync(join(output, 'keep'), 'Keep');
  assert.throws(() => exportSource({ repo, output }), /EEXIST/);
  assert.equal(readFileSync(join(output, 'keep'), 'utf8'), 'Keep');
  const file = join(root, 'file');
  writeFileSync(file, 'Keep');
  assert.throws(() => exportSource({ repo, output: file }), /EEXIST/);
  assert.equal(readFileSync(file, 'utf8'), 'Keep');
  symlinkSync(output, join(root, 'link'));
  assert.throws(() => exportSource({ repo, output: join(root, 'link') }), /EEXIST/);
  assert.throws(() => exportSource({ repo, output: join(repo, 'export') }), /outside/);
  symlinkSync(repo, join(root, 'repo-link'));
  assert.throws(() => exportSource({ repo, output: join(root, 'repo-link', 'export') }), /outside/);
});

test('refuses tracked runtime paths rather than silently producing an incomplete source tree', (t) => {
  const { root, repo, git } = fixture(t);
  writeFileSync(join(repo, '.env'), 'PRIVATE');
  git('add', '-f', '.env');
  git('commit', '-qm', 'unsafe');
  assert.throws(() => exportSource({ repo, output: join(root, 'a') }), /potentially private/);
});

test('refuses symlinks and private key material', (t) => {
  const { root, repo, git } = fixture(t);
  symlinkSync('/etc/passwd', join(repo, 'link'));
  git('add', 'link');
  git('commit', '-qm', 'symlink');
  assert.throws(() => exportSource({ repo, output: join(root, 'a') }), /symlink\/submodule/);
  git('rm', 'link');
  writeFileSync(join(repo, 'unsafe.txt'), ['-----BEGIN ', 'PRIVATE KEY-----'].join(''));
  git('add', 'unsafe.txt');
  git('commit', '-qm', 'key');
  assert.throws(() => exportSource({ repo, output: join(root, 'b') }), /private key material/);
});

test('portable archive supports long nested paths and executable modes', (t) => {
  const { root, repo, git } = fixture(t);
  const dir = 'a'.repeat(90);
  mkdirSync(join(repo, dir));
  writeFileSync(join(repo, dir, 'run.sh'), '#!/bin/sh\necho ok\n');
  git('add', '.');
  git('update-index', '--chmod=+x', `${dir}/run.sh`);
  git('commit', '-qm', 'executable');
  const result = exportSource({ repo, commit: git('rev-parse', 'HEAD'), output: join(root, 'a') });
  const archive = join(root, 'a', result.archive);
  const listing = execFileSync('tar', ['-tvf', archive], { encoding: 'utf8' });
  assert.match(listing, /-rwxr-xr-x/);
  assert.equal(
    execFileSync('tar', ['-xOf', archive, `bible-companion/${dir}/run.sh`], { encoding: 'utf8' }),
    '#!/bin/sh\necho ok\n',
  );
});

test('refuses invalid UTF-8 Git names instead of silently renaming or colliding', (t) => {
  const { root, repo, git } = fixture(t);
  // Git trees can contain raw-byte names even when the host filesystem rejects them.
  // Build those exact objects directly so the security case also runs on macOS.
  const blob = execFileSync('git', ['-C', repo, 'hash-object', '-w', '--stdin'], { input: 'Exact filename matters', encoding: 'utf8' }).trim();
  const entries = Buffer.concat([0xfe, 0xff].map(byte => Buffer.concat([
    Buffer.from(`100644 blob ${blob}\t`), Buffer.from([byte]), Buffer.from('.txt\0'),
  ])));
  const tree = execFileSync('git', ['-C', repo, 'mktree', '-z'], { input: entries, encoding: 'utf8' }).trim();
  const rawCommit = execFileSync('git', ['-C', repo, 'commit-tree', tree, '-m', 'raw byte names'], { encoding: 'utf8' }).trim();
  assert.throws(
    () => exportSource({ repo, commit: rawCommit, output: join(root, 'a') }),
    /encoded data was not valid/,
  );
});

test('commit and blob replacement refs cannot change exact-object archive bytes', (t) => {
  const { root, repo, git, commit } = fixture(t);
  const originalBlob = git('rev-parse', `${commit}:hello.txt`);
  writeFileSync(join(repo, 'hello.txt'), 'Replacement bytes');
  git('add', '.');
  git('commit', '-qm', 'replacement');
  const replacement = git('rev-parse', 'HEAD');
  const replacementBlob = git('rev-parse', `${replacement}:hello.txt`);
  git('replace', commit, replacement);
  git('replace', originalBlob, replacementBlob);
  const result = exportSource({ repo, commit, output: join(root, 'a') });
  assert.equal(result.commit, commit);
  assert.equal(
    execFileSync('tar', ['-xOf', join(root, 'a', result.archive), 'bible-companion/hello.txt'], {
      encoding: 'utf8',
    }),
    'Committed source\n',
  );
  assert.equal(result.files.find((file) => file.path === 'hello.txt').gitBlob, originalBlob);
});
