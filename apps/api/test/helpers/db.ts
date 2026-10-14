import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { Env } from '../../src/types';
import { sha256 } from '@bible/core';
/** Real SQLite schema/triggers behind the narrow D1 API used by the Worker. */
export class TestDatabase {
  readonly sqlite = new DatabaseSync(':memory:');
  constructor() {
    this.sqlite.exec('PRAGMA foreign_keys=ON');
    const dir = fileURLToPath(new URL('../../migrations/', import.meta.url));
    for (const name of readdirSync(dir)
      .filter((x) => x.endsWith('.sql'))
      .sort())
      this.sqlite.exec(readFileSync(dir + name, 'utf8'));
  }
  prepare(sql: string) {
    return new TestStatement(this, sql);
  }
  async batch(statements: TestStatement[]) {
    this.sqlite.exec('BEGIN');
    try {
      const results = [];
      for (const s of statements) results.push(s.allSync());
      this.sqlite.exec('COMMIT');
      return results;
    } catch (e) {
      this.sqlite.exec('ROLLBACK');
      throw e;
    }
  }
  async exec(sql: string) {
    this.sqlite.exec(sql);
    return { count: 1, duration: 0 };
  }
}
class TestStatement {
  constructor(
    readonly db: TestDatabase,
    readonly sql: string,
    readonly params: unknown[] = [],
  ) {}
  bind(...params: unknown[]) {
    return new TestStatement(this.db, this.sql, params);
  }
  async first<T = Record<string, unknown>>(column?: string): Promise<T | null> {
    const r = this.db.sqlite.prepare(this.sql).get(...(this.params as never[])) as
      Record<string, unknown> | undefined;
    return (r ? (column ? r[column] : r) : null) as T | null;
  }
  allSync<T = Record<string, unknown>>() {
    const results = this.db.sqlite.prepare(this.sql).all(...(this.params as never[])) as T[];
    return {
      results,
      success: true,
      meta: { changes: Number(this.db.sqlite.prepare('SELECT changes() AS n').get()?.n ?? 0) },
    };
  }
  async all<T = Record<string, unknown>>() {
    return this.allSync<T>();
  }
  async run() {
    return this.all();
  }
}
export function testEnv(db = new TestDatabase()): Env {
  return {
    DB: db as unknown as D1Database,
    ENVIRONMENT: 'development',
    RP_ID: 'localhost',
    AUTH_ORIGIN: 'http://localhost:8787',
    NATIVE_CALLBACK: 'biblecompanion://auth/callback',
    AI_ENABLED: 'false',
    CONNECTED_MODELS: '[]',
    TERMS_REVIEWED_MODELS: '[]',
    TERMS_REVIEW_VERSION: '',
    DEFAULT_MODEL_ID: '@cf/google/gemma-4-26b-a4b-it',
    DAILY_APP_BUDGET: '9000',
    DAILY_USER_BUDGET: '2000',
    AI_RESERVATION_UNITS: '500',
  };
}
export async function seedUser(
  env: Env,
  id = crypto.randomUUID(),
  role: 'owner' | 'member' = 'member',
  debugEnabled = role === 'owner',
) {
  // Existing developer fixtures explicitly opt in; production has no default access.
  if (debugEnabled) env.DEBUG_ACCOUNT_IDS = JSON.stringify([...JSON.parse(env.DEBUG_ACCOUNT_IDS ?? '[]'), id]);
  const token = crypto.randomUUID();
  const t = Math.floor(Date.now() / 1000);
  await env.DB.prepare('INSERT INTO users(id,display_name,role,created_at) VALUES(?,?,?,?)')
    .bind(id, 'Test reader', role, t)
    .run();
  await env.DB.prepare(
    'INSERT INTO sessions(token_hash,user_id,expires_at,created_at) VALUES(?,?,?,?)',
  )
    .bind(await sha256(token), id, t + 3600, t)
    .run();
  return {
    id,
    token,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  };
}
