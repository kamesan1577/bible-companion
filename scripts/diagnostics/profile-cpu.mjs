import { createRequire } from 'node:module';
import { createHash, generateKeyPairSync, randomBytes, sign } from 'node:crypto';
import { writeFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const repo = fileURLToPath(new URL('../../', import.meta.url));
const require = createRequire(`${repo}/package.json`);
const {
  verifyRegistrationResponse,
  verifyAuthenticationResponse,
} = require('@simplewebauthn/server');
const dir = mkdtempSync(join(tmpdir(), 'bible-cpu-diagnostic-')) + '/';
const hash = (b) => createHash('sha256').update(b).digest();
const b64 = (b) => Buffer.from(b).toString('base64url');
function header(major, n) {
  if (n < 24) return Buffer.from([(major << 5) | n]);
  if (n < 256) return Buffer.from([(major << 5) | 24, n]);
  const b = Buffer.alloc(3);
  b[0] = (major << 5) | 25;
  b.writeUInt16BE(n, 1);
  return b;
}
function cbor(value) {
  if (typeof value === 'number') return value < 0 ? header(1, -1 - value) : header(0, value);
  if (typeof value === 'string') {
    const b = Buffer.from(value);
    return Buffer.concat([header(3, b.length), b]);
  }
  if (Buffer.isBuffer(value)) return Buffer.concat([header(2, value.length), value]);
  if (value instanceof Map)
    return Buffer.concat([
      header(5, value.size),
      ...Array.from(value, ([k, v]) => Buffer.concat([cbor(k), cbor(v)])),
    ]);
  throw new Error('unsupported CBOR fixture value');
}
const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const jwk = publicKey.export({ format: 'jwk' });
const cose = cbor(
  new Map([
    [1, 2],
    [3, -7],
    [-1, 1],
    [-2, Buffer.from(jwk.x, 'base64url')],
    [-3, Buffer.from(jwk.y, 'base64url')],
  ]),
);
const credential = randomBytes(32),
  challenge = b64(randomBytes(32));
const expectedOrigin = 'https://review.example',
  expectedRPID = 'review.example';
const client = (type) =>
  Buffer.from(JSON.stringify({ type, challenge, origin: expectedOrigin, crossOrigin: false }));
const registrationClient = client('webauthn.create');
const registrationData = Buffer.concat([
  hash(expectedRPID),
  Buffer.from([0x45]),
  Buffer.alloc(4),
  Buffer.alloc(16),
  Buffer.from([0, 32]),
  credential,
  cose,
]);
const attestation = cbor(
  new Map([
    ['fmt', 'packed'],
    [
      'attStmt',
      new Map([
        ['alg', -7],
        [
          'sig',
          sign('sha256', Buffer.concat([registrationData, hash(registrationClient)]), privateKey),
        ],
      ]),
    ],
    ['authData', registrationData],
  ]),
);
const registration = {
  response: {
    id: b64(credential),
    rawId: b64(credential),
    type: 'public-key',
    clientExtensionResults: {},
    response: {
      clientDataJSON: b64(registrationClient),
      attestationObject: b64(attestation),
      transports: ['internal'],
    },
  },
  expectedChallenge: challenge,
  expectedOrigin,
  expectedRPID,
  requireUserVerification: true,
};
const assertionClient = client('webauthn.get');
const assertionData = Buffer.concat([
  hash(expectedRPID),
  Buffer.from([0x05]),
  Buffer.from([0, 0, 0, 1]),
]);
const assertion = {
  response: {
    id: b64(credential),
    rawId: b64(credential),
    type: 'public-key',
    clientExtensionResults: {},
    response: {
      clientDataJSON: b64(assertionClient),
      authenticatorData: b64(assertionData),
      signature: b64(
        sign('sha256', Buffer.concat([assertionData, hash(assertionClient)]), privateKey),
      ),
    },
  },
  expectedChallenge: challenge,
  expectedOrigin,
  expectedRPID,
  requireUserVerification: true,
  credential: {
    id: b64(credential),
    publicKey: new Uint8Array(cose),
    counter: 0,
    transports: ['internal'],
  },
};
function stats(samples) {
  const summarize = (key) => {
    const values = samples.map((s) => s[key]).sort((a, b) => a - b);
    return {
      median: values[Math.floor(values.length / 2)],
      p95: values[Math.min(values.length - 1, Math.ceil(values.length * 0.95) - 1)],
      max: values.at(-1),
    };
  };
  return {
    samples: samples.length,
    cpuMs: summarize('cpuMs'),
    userMs: summarize('userMs'),
    systemMs: summarize('systemMs'),
    wallMs: summarize('wallMs'),
    raw: samples,
  };
}
async function measured(fn) {
  const cpu = process.cpuUsage(),
    time = performance.now();
  const result = await fn();
  const used = process.cpuUsage(cpu);
  if (!result.verified) throw new Error('fixture failed cryptographic verification');
  return {
    cpuMs: (used.user + used.system) / 1000,
    userMs: used.user / 1000,
    systemMs: used.system / 1000,
    wallMs: performance.now() - time,
  };
}
async function profile(fn) {
  const first = await measured(fn);
  for (let i = 0; i < 3; i++) await fn();
  const samples = [];
  for (let i = 0; i < 25; i++) samples.push(await measured(fn));
  return { firstCall: first, warmupCount: 3, ...stats(samples) };
}
const registrationProfile = await profile(() => verifyRegistrationResponse(registration));
const assertionProfile = await profile(() => verifyAuthenticationResponse(assertion));
const bundlePath = `${dir}api-node-profile.cjs`;
await require('esbuild').build({
  entryPoints: [`${repo}/apps/api/src/index.ts`],
  outfile: bundlePath,
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node24',
  logLevel: 'silent',
});
const cold = [];
for (let i = 0; i < 8; i++) {
  const child = spawnSync(
    process.execPath,
    [
      '-e',
      `const cpu=process.cpuUsage(),time=performance.now();require(${JSON.stringify(bundlePath)});const used=process.cpuUsage(cpu);process.stdout.write(JSON.stringify({cpuMs:(used.user+used.system)/1000,userMs:used.user/1000,systemMs:used.system/1000,wallMs:performance.now()-time}));`,
    ],
    { encoding: 'utf8', timeout: 30000 },
  );
  if (child.status !== 0) throw new Error(child.stderr || 'cold import process failed');
  cold.push(JSON.parse(child.stdout));
}
const report = {
  measuredAt: new Date().toISOString(),
  node: process.version,
  description:
    'Offline Node CPU diagnostics; genuine locally signed ES256 packed self-attestation and assertion, no browser or remote service.',
  limitations: [
    'process.cpuUsage is whole-process user+system CPU, including runtime scheduling and worker-thread crypto activity where counted; it is not isolate-billed CPU.',
    'Cryptographic fixtures are generated and signed before measurement; verifier measurements exclude database/auth route work and module import.',
    'Cold initialization is fresh Node child require of a Node-target bundled API: compilation excluded; filesystem read, parsing and evaluation included. Node process startup excluded; filesystem cache may be warm.',
    'SQLite overhead is excluded here and included in the separate local route wall-time profile.',
    'These results do not establish Cloudflare Free 10ms CPU compliance. Deployed workload CPU measurement remains a launch gate; no automatic paid upgrade.',
  ],
  registration: registrationProfile,
  assertion: assertionProfile,
  coldBundledModule: stats(cold),
};
writeFileSync(`${dir}cpu-profile.json`, JSON.stringify(report, null, 2) + '\n');
console.log(`Raw diagnostic report: ${dir}cpu-profile.json`);
console.log(
  JSON.stringify(
    {
      registration: registrationProfile.cpuMs,
      assertion: assertionProfile.cpuMs,
      cold: report.coldBundledModule.cpuMs,
    },
    null,
    2,
  ),
);
