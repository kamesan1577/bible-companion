import { describe, it, expect } from 'vitest';
import { validateAuthConfig } from '../src/auth';
import { testEnv } from './helpers/db';
describe('stable authentication transport configuration', () => {
  it('allows only HTTPS or the explicit development localhost HTTP exception', () => {
    const env = testEnv();
    expect(() => validateAuthConfig(env)).not.toThrow();
    expect(() =>
      validateAuthConfig({ ...env, AUTH_ORIGIN: 'https://localhost:8787' }),
    ).not.toThrow();
    for (const scheme of ['ftp', 'ws', 'wss', 'file'])
      expect(() =>
        validateAuthConfig({ ...env, AUTH_ORIGIN: `${scheme}://localhost:8787` }),
      ).toThrow();
    expect(() => validateAuthConfig({ ...env, ENVIRONMENT: 'production' })).toThrow();
  });
});
