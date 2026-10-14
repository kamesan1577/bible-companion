#!/usr/bin/env node
// Deliberately uses Git objects, never worktree file contents or git archive attributes.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, resolve, relative, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
function git(repo, ...args) {
  return execFileSync('git', ['--no-replace-objects', '-C', repo, ...args], {
    maxBuffer: 256 * 1024 * 1024,
  });
}
function header(path, size, executable) {
  const block = Buffer.alloc(512);
  let name = path;
  let prefix = '';
  if (Buffer.byteLength(name) > 100) {
    const split = [...path.matchAll(/\//g)]
      .map((m) => m.index)
      .reverse()
      .find(
        (i) =>
          Buffer.byteLength(path.slice(0, i)) <= 155 && Buffer.byteLength(path.slice(i + 1)) <= 100,
      );
    if (split === undefined) throw new Error(`Path cannot fit portable ustar: ${path}`);
    prefix = path.slice(0, split);
    name = path.slice(split + 1);
  }
  block.write(name, 0, 100);
  const octal = (value, start, length) => {
    const digits = value.toString(8);
    if (digits.length >= length) throw new Error('ustar numeric field overflow');
    block.write(digits.padStart(length - 1, '0') + '\0', start, length);
  };
  octal(executable ? 0o755 : 0o644, 100, 8);
  octal(0, 108, 8);
  octal(0, 116, 8);
  octal(size, 124, 12);
  octal(0, 136, 12);
  block.fill(32, 148, 156);
  block.write('0', 156);
  block.write('ustar\0', 257);
  block.write('00', 263);
  block.write(prefix, 345, 155);
  const sum = block.reduce((a, b) => a + b, 0);
  block.write(sum.toString(8).padStart(6, '0') + '\0 ', 148, 8);
  return block;
}
function assertSourcePath(path) {
  const parts = path.split('/');
  const forbidden = new Set(['.git', 'node_modules', '.cache', '.wrangler', 'dist', 'coverage']);
  if (
    path.startsWith('/') ||
    /[\x00-\x1f\x7f\\]/.test(path) ||
    parts.some((p) => p === '..' || forbidden.has(p)) ||
    parts.some((p) => /^\.env(?:\.|$)/.test(p) && p !== '.env.example') ||
    /(?:^|\/)(?:\.dev\.vars(?:\..*)?|wrangler\.(?:production|assets|operator)\.json|id_rsa|id_ed25519)$/.test(
      path,
    ) ||
    /\.(?:log|sqlite|sqlite3|db|pem|p12|key)$/i.test(path)
  ) {
    throw new Error(`Refusing potentially private/generated tracked path: ${path}`);
  }
}
export function exportSource({ repo = process.cwd(), commit: requestedCommit, output }) {
  if (!output) throw new Error('--output is required (a new directory outside the repository)');
  repo = realpathSync(git(repo, 'rev-parse', '--show-toplevel').toString().trim());
  if (requestedCommit !== undefined && !/^[a-f0-9]{7,64}$/i.test(requestedCommit)) {
    throw new Error('--commit must be a commit object ID, not a moving branch or tag');
  }
  if (
    !requestedCommit &&
    git(repo, 'status', '--porcelain=v1', '--untracked-files=all', '--ignore-submodules=none')
      .length
  ) {
    throw new Error('Dirty working tree: commit changes or supply an explicit --commit object ID');
  }
  const commit = git(repo, 'rev-parse', '--verify', `${requestedCommit ?? 'HEAD'}^{commit}`)
    .toString()
    .trim();
  const tree = git(repo, 'rev-parse', `${commit}^{tree}`).toString().trim();
  const destination = resolve(output);
  const canonicalDestination = resolve(
    realpathSync(dirname(destination)),
    destination.split('/').at(-1),
  );
  const rel = relative(repo, canonicalDestination);
  if (!rel || (!rel.startsWith('..' + '/') && rel !== '..' && !isAbsolute(rel))) {
    throw new Error('Output must be outside the repository');
  }
  // Git permits arbitrary filename bytes; reject invalid UTF-8 rather than renaming paths.
  const entries = new TextDecoder('utf-8', { fatal: true })
    .decode(git(repo, 'ls-tree', '-rz', '--full-tree', commit))
    .split('\0')
    .filter(Boolean);
  const chunks = [];
  const files = [];
  for (const entry of entries) {
    const match = /^(\d+) (\w+) ([a-f0-9]+)\t([\s\S]+)$/.exec(entry);
    if (!match) throw new Error('Unexpected Git tree entry');
    const [, mode, type, oid, path] = match;
    assertSourcePath(path);
    if (type !== 'blob' || !['100644', '100755'].includes(mode)) {
      throw new Error(`Unsupported source entry (symlink/submodule): ${path}`);
    }
    const data = git(repo, 'cat-file', 'blob', oid);
    // Conservative guard, not a replacement for human review of committed source.
    if (/-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/.test(data.toString('utf8'))) {
      throw new Error(`Refusing private key material: ${path}`);
    }
    chunks.push(
      header(`bible-companion/${path}`, data.length, mode === '100755'),
      data,
      Buffer.alloc((512 - (data.length % 512)) % 512),
    );
    files.push({ path, mode, gitBlob: oid, bytes: data.length, sha256: sha256(data) });
  }
  chunks.push(Buffer.alloc(1024));
  const archive = Buffer.concat(chunks);
  const archiveName = `bible-companion-${commit}.tar`;
  const manifest = {
    schemaVersion: 1,
    commit,
    tree,
    archive: archiveName,
    archiveBytes: archive.length,
    archiveSha256: sha256(archive),
    format: 'POSIX ustar; Git tree order; uid/gid/mtime=0; prefix=bible-companion/',
    files,
  };
  // Exclusive directory creation refuses existing files/directories/symlinks, including --output reuse.
  mkdirSync(destination, { mode: 0o700 });
  try {
    writeFileSync(resolve(destination, archiveName), archive, { flag: 'wx', mode: 0o600 });
    writeFileSync(resolve(destination, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n', {
      flag: 'wx',
      mode: 0o600,
    });
  } catch (error) {
    rmSync(destination, { recursive: true, force: true });
    throw error;
  }
  return manifest;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = {};
    const args = process.argv.slice(2);
    while (args.length) {
      const key = args.shift();
      if (
        !['--repo', '--commit', '--output'].includes(key) ||
        !args.length ||
        args[0].startsWith('--') ||
        key.slice(2) in options
      ) {
        throw new Error(
          'Usage: node scripts/export-source.mjs [--repo PATH] [--commit OBJECT_ID] --output NEW_DIRECTORY',
        );
      }
      options[key.slice(2)] = args.shift();
    }
    const result = exportSource(options);
    console.log(
      JSON.stringify(
        { commit: result.commit, archive: result.archive, sha256: result.archiveSha256 },
        null,
        2,
      ),
    );
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
