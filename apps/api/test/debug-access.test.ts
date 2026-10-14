import { describe, it, expect } from 'vitest';
import worker from '../src/index';
const app = { request: (path: string, init: RequestInit, env: ReturnType<typeof testEnv>) => worker.fetch(new Request('http://localhost' + path, init), env) };
import { testEnv, seedUser } from './helpers/db';
describe('explicit developer account authorization', () => {
  it('denies owners by default, and ignores caller-supplied flags', async () => {
    const env = testEnv(); const user = await seedUser(env, crypto.randomUUID(), 'owner', false);
    const me = await app.request('/v1/me', { headers: user.headers }, env);
    expect(((await me.json()) as {user:{canDebug:boolean}}).user.canDebug).toBe(false);
    for (const path of ['/v1/developer/models', '/v1/developer/comparisons']) {
      expect((await app.request(path, { headers: { ...user.headers, 'X-Debug': 'true' } }, env)).status).toBe(403);
    }
    expect((await app.request('/v1/developer/model-preference', {method:'PUT',headers:user.headers,body:'{}'},env)).status).toBe(403);
  });
  it('requires both explicit designation and owner role', async () => {
    const env = testEnv(); const member = await seedUser(env, crypto.randomUUID(), 'member', true);
    expect((await app.request('/v1/developer/models', {headers:member.headers},env)).status).toBe(403);
    const owner = await seedUser(env, crypto.randomUUID(), 'owner', true);
    expect((await app.request('/v1/developer/models', {headers:owner.headers},env)).status).toBe(200);
    env.DEBUG_ACCOUNT_IDS = 'invalid';
    expect((await app.request('/v1/developer/models', {headers:owner.headers},env)).status).toBe(403);
  });
});
