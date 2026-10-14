#!/usr/bin/env node
import { readFile, writeFile, mkdir, rename, lstat } from 'node:fs/promises';
import { resolve, relative, isAbsolute, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { gunzipSync } from 'node:zlib';
import {
  WEBP_SOURCE,
  WEBP_PINNED_SNAPSHOT,
  prepareScriptureCorpus,
  scriptureSha256,
} from '../packages/core/src/scripture-corpus.ts';

const root = resolve(fileURLToPath(new URL('../', import.meta.url)));
const cache = resolve(root, '.cache/scripture');
const defaultArchive = resolve(cache, 'engwebp_usfx.zip');
const defaultOutput = resolve(cache, 'prepared');
const bundled = resolve(root, 'data/scripture/webp-2026-10-13');
const MAX_ARCHIVE_BYTES = 20 * 1024 * 1024;
const MAX_XML_BYTES = 64 * 1024 * 1024;
const usage = `Usage: node scripts/scripture-corpus.mjs <fetch|prepare|verify|restore-bundled|verify-bundled> [--archive PATH] [--out-dir PATH]

fetch    Download the code-pinned public-domain eBible archive from its official fixed HTTPS URL.
prepare  Verify archive/XML hashes and prepare a 66-book snapshot locally, without network access.
verify   Reprepare in memory and compare every generated local artifact byte-for-byte.
restore-bundled  Restore hash-pinned bundled outputs offline, without original XML or Python.
verify-bundled   Verify bundled output integrity only; this does not reparse original XML.

Defaults: .cache/scripture/engwebp_usfx.zip and .cache/scripture/prepared/.
Output directories must stay inside this repository's .cache/scripture/.
Requires Node >=24; prepare/verify additionally need Python 3 for standard-library ZIP reading.
No D1 writes, account access, remote deployment or model calls. A changed publisher archive fails closed.
`;

async function safeCacheDestination(path) {
  const absolute = resolve(path);
  const rel = relative(cache, absolute);
  if (rel.startsWith('..') || isAbsolute(rel))
    throw new Error('Output must remain inside .cache/scripture');
  // Do not write through symlinks, including the .cache directory itself.
  for (let p = absolute; p !== root; p = dirname(p)) {
    const info = await lstat(p).catch((e) => {
      if (e.code === 'ENOENT') return null;
      throw e;
    });
    if (info?.isSymbolicLink()) throw new Error('Cache output cannot traverse symlinks');
  }
  return absolute;
}
async function atomicWrite(path, bytes) {
  await safeCacheDestination(path);
  await mkdir(dirname(path), { recursive: true });
  const temporary = `${path}.${process.pid}.tmp`;
  await writeFile(temporary, bytes, { flag: 'wx', mode: 0o600 });
  await rename(temporary, path);
}
async function readArchive(path) {
  const info = await lstat(path);
  if (!info.isFile() || info.size > MAX_ARCHIVE_BYTES)
    throw new Error('Archive must be a regular file no larger than 20 MiB');
  const bytes = await readFile(path);
  const digest = await scriptureSha256(bytes);
  if (digest !== WEBP_PINNED_SNAPSHOT.archiveSha256)
    throw new Error(
      `Archive SHA-256 mismatch: ${digest}. Do not bypass this check; review a new publisher snapshot separately.`,
    );
  return bytes;
}
function extractXml(archive) {
  // No archive path is extracted. Only the one expected regular member is streamed to stdout.
  const code = `import io,sys,zipfile,stat
z=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))
m=[i for i in z.infolist() if i.filename==${JSON.stringify(WEBP_SOURCE.archiveMember)}]
if len(m)!=1: raise ValueError('Expected exactly one named USFX member')
i=m[0]
if i.file_size>${MAX_XML_BYTES} or i.flag_bits & 1 or i.is_dir() or stat.S_ISLNK(i.external_attr >> 16): raise ValueError('Unsafe ZIP member')
if i.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED): raise ValueError('Unsupported ZIP compression')
data=z.read(i)
if len(data)!=i.file_size: raise ValueError('Incorrect ZIP member size')
sys.stdout.buffer.write(data)
`;
  const result = spawnSync('python3', ['-c', code], {
    input: archive,
    maxBuffer: MAX_XML_BYTES + 1024,
    timeout: 30_000,
  });
  if (result.error || result.status !== 0)
    throw new Error(
      `Bounded ZIP extraction failed: ${result.error?.message ?? result.stderr.toString().slice(0, 1000)}`,
    );
  return result.stdout;
}
async function fetchPinnedArchive() {
  const response = await fetch(WEBP_SOURCE.sourceURL, {
    redirect: 'error',
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok || !response.body)
    throw new Error(`Publisher download failed: HTTP ${response.status}`);
  const claimedLength = Number(response.headers.get('content-length') ?? 0);
  if (claimedLength > MAX_ARCHIVE_BYTES) throw new Error('Publisher archive exceeds 20 MiB');
  const chunks = [];
  let size = 0;
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > MAX_ARCHIVE_BYTES) throw new Error('Publisher archive exceeds 20 MiB');
    chunks.push(chunk);
  }
  const bytes = Buffer.concat(chunks);
  const digest = await scriptureSha256(bytes);
  if (digest !== WEBP_PINNED_SNAPSHOT.archiveSha256)
    throw new Error(
      `Publisher archive changed (${digest}); existing cache was not replaced. Review and code-pin a new snapshot before importing.`,
    );
  await atomicWrite(defaultArchive, bytes);
  await atomicWrite(
    resolve(cache, 'latest-download-receipt.json'),
    JSON.stringify(
      {
        sourceURL: WEBP_SOURCE.sourceURL,
        retrievedAt: new Date().toISOString(),
        archiveSha256: digest,
      },
      null,
      2,
    ) + '\n',
  );
  return { archive: defaultArchive, archiveSha256: digest, bytes: size };
}

async function readBoundedRegularFile(path, maximum) {
  const info = await lstat(path);
  if (!info.isFile() || info.size > maximum)
    throw new Error('Invalid or oversized bundled artifact');
  const bytes = await readFile(path);
  if (bytes.length > maximum) throw new Error('Bundled artifact changed size while reading');
  return bytes;
}
async function verifyBundledArtifacts() {
  const manifestBytes = await readBoundedRegularFile(
    resolve(bundled, 'manifest.json'),
    1024 * 1024,
  );
  const manifestSha256 = await scriptureSha256(manifestBytes);
  if (manifestSha256 !== WEBP_PINNED_SNAPSHOT.manifestSha256)
    throw new Error('Bundled manifest SHA-256 mismatch');
  const manifestJson = new TextDecoder('utf-8', { fatal: true }).decode(manifestBytes);
  const manifest = JSON.parse(manifestJson);
  const hashFile = `${manifestSha256}  manifest.json\n`;
  const savedHash = await readBoundedRegularFile(resolve(bundled, 'manifest.sha256'), 256);
  if (savedHash.toString('utf8') !== hashFile) throw new Error('Bundled manifest.sha256 mismatch');
  const artifacts = {};
  for (const [name, expected] of [
    ['verses', manifest.hash.verses],
    ['unversified', manifest.hash.unversified],
  ]) {
    const compressed = await readBoundedRegularFile(
      resolve(bundled, `${name}.ndjson.gz`),
      5 * 1024 * 1024,
    );
    if (
      compressed.length < 10 ||
      compressed[0] !== 31 ||
      compressed[1] !== 139 ||
      compressed.readUInt32LE(4) !== 0
    )
      throw new Error('Bundled gzip must use a deterministic zero timestamp');
    const bytes = gunzipSync(compressed, { maxOutputLength: MAX_XML_BYTES });
    if ((await scriptureSha256(bytes)) !== expected)
      throw new Error(`Bundled ${name} output SHA-256 mismatch`);
    artifacts[`${name}.ndjson`] = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  }
  artifacts['manifest.json'] = manifestJson;
  artifacts['manifest.sha256'] = hashFile;
  return { artifacts, manifest, manifestSha256 };
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (['--help', '-h', undefined].includes(command)) {
    console.log(usage);
    return;
  }
  if (!['fetch', 'prepare', 'verify', 'restore-bundled', 'verify-bundled'].includes(command))
    throw new Error('Unknown command; use --help');
  let archivePath = defaultArchive;
  let output = defaultOutput;
  const seen = new Set();
  for (let i = 0; i < args.length; i += 2) {
    if (
      !['--archive', '--out-dir'].includes(args[i]) ||
      !args[i + 1] ||
      args[i + 1].startsWith('--') ||
      seen.has(args[i])
    )
      throw new Error('Unknown, duplicate or incomplete option');
    seen.add(args[i]);
    if (args[i] === '--archive') archivePath = resolve(args[i + 1]);
    else output = resolve(args[i + 1]);
  }
  if (command === 'fetch') {
    if (args.length)
      throw new Error('fetch accepts no options and only writes its fixed local cache');
    console.log(JSON.stringify(await fetchPinnedArchive(), null, 2));
    return;
  }
  if (command === 'restore-bundled' || command === 'verify-bundled') {
    if (seen.has('--archive') || (command === 'verify-bundled' && args.length))
      throw new Error(
        'Bundled verification takes no archive; only restore-bundled accepts --out-dir',
      );
    const verified = await verifyBundledArtifacts();
    if (command === 'restore-bundled') {
      await safeCacheDestination(output);
      for (const [name, bytes] of Object.entries(verified.artifacts))
        await atomicWrite(resolve(output, name), bytes);
    }
    console.log(
      JSON.stringify(
        {
          command,
          verification: 'bundled-output-integrity',
          originalXmlReparsed: false,
          manifestSha256: verified.manifestSha256,
          books: verified.manifest.bookCount,
          verses: verified.manifest.verseCount,
          ...(command === 'restore-bundled' ? { output } : {}),
        },
        null,
        2,
      ),
    );
    return;
  }
  await safeCacheDestination(output);
  const archive = await readArchive(archivePath);
  const prepared = await prepareScriptureCorpus(extractXml(archive), WEBP_PINNED_SNAPSHOT);
  const manifestJson = JSON.stringify(prepared.manifest, null, 2) + '\n';
  const manifestSha256 = await scriptureSha256(new TextEncoder().encode(manifestJson));
  if (manifestSha256 !== WEBP_PINNED_SNAPSHOT.manifestSha256)
    throw new Error(
      'Generated manifest differs from the code-pinned snapshot; review parser/output changes before updating the pin.',
    );
  const artifacts = {
    'verses.ndjson': prepared.versesNdjson,
    'unversified.ndjson': prepared.unversifiedNdjson,
    'manifest.json': manifestJson,
    'manifest.sha256': `${manifestSha256}  manifest.json\n`,
  };
  for (const [name, contents] of Object.entries(artifacts)) {
    const path = resolve(output, name);
    if (command === 'verify') {
      if ((await readFile(path, 'utf8')) !== contents)
        throw new Error(`Prepared artifact differs from pinned source: ${name}`);
    } else await atomicWrite(path, contents);
  }
  console.log(
    JSON.stringify(
      {
        command,
        output,
        manifestSha256,
        version: prepared.manifest.version,
        books: prepared.manifest.bookCount,
        verses: prepared.manifest.verseCount,
        nonempty: prepared.manifest.nonemptyVerseCount,
        unsupported: prepared.manifest.unsupportedVerses,
        empty: prepared.manifest.emptyVerses,
        missingCanonical: prepared.manifest.missingCanonicalVerses,
      },
      null,
      2,
    ),
  );
}
main().catch((error) => {
  console.error(`Scripture corpus: ${error.message}`);
  process.exitCode = 1;
});
