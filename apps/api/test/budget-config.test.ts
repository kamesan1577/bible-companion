import { describe, it, expect } from 'vitest';
import { reserveBudget } from '../src/budget';
import { testEnv, seedUser } from './helpers/db';
describe('runtime generation budget configuration', () => {
  it('never turns malformed or zero limits into an implicit spending allowance', async () => {
    for (const value of ['0', '-1', 'NaN', 'Infinity', '1.5', '1e3', ' 9000', '9999999999']) {
      const env = testEnv(),
        user = await seedUser(env);
      env.DAILY_APP_BUDGET = value;
      await expect(reserveBudget(env, user.id, 'invalid-config', 1)).rejects.toThrow();
      expect(await env.DB.prepare('SELECT COUNT(*) AS n FROM budget_reservations').first()).toEqual(
        { n: 0 },
      );
    }
  });
});
