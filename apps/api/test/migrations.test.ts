import { describe, it, expect } from 'vitest';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const directory = fileURLToPath(new URL('../migrations/', import.meta.url));
const files = readdirSync(directory)
  .filter((x) => x.endsWith('.sql'))
  .sort();
function migrate(db: DatabaseSync, name: string) {
  db.exec('BEGIN');
  try {
    db.exec(readFileSync(directory + name, 'utf8'));
    db.prepare('INSERT INTO migrations(name) VALUES(?)').run(name);
    db.exec('COMMIT');
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}
function applyPending(db: DatabaseSync) {
  for (const name of files)
    if (!db.prepare('SELECT name FROM migrations WHERE name=?').get(name)) migrate(db, name);
}
function db() {
  const db = new DatabaseSync(':memory:');
  db.exec('PRAGMA foreign_keys=ON; CREATE TABLE migrations(name TEXT PRIMARY KEY)');
  return db;
}
describe('migration lifecycle', () => {
  it('fresh and repeated migration passes are deterministic', () => {
    const database = db();
    applyPending(database);
    expect(database.prepare('SELECT COUNT(*) AS n FROM public_sources').get()?.n).toBe(9);
    expect(database.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    const before = database
      .prepare("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name")
      .all();
    applyPending(database);
    expect(
      database.prepare("SELECT name,sql FROM sqlite_master WHERE type='table' ORDER BY name").all(),
    ).toEqual(before);
    expect(database.prepare('SELECT COUNT(*) AS n FROM migrations').get()?.n).toBe(files.length);
  });
  it('upgrades existing data without losing account/import/conversation history', () => {
    const database = db();
    migrate(database, files[0]);
    database.exec(
      "INSERT INTO users(id,display_name,role,created_at) VALUES('u','reader','member',1); INSERT INTO imports(id,user_id,idempotency_key,request_hash,ranges_json,created_at) VALUES('i','u','k','h','[]',1); INSERT INTO conversations(id,user_id,import_id,passage_json,created_at) VALUES('c','u','i','{}',1); INSERT INTO generation_requests(id,user_id,conversation_id,request_hash,status,result_json,created_at,updated_at) VALUES('r','u','c','h','complete','{}',1,1)",
    );
    applyPending(database);
    expect(database.prepare('SELECT COUNT(*) AS n FROM users').get()?.n).toBe(1);
    expect(database.prepare('SELECT result_json FROM generation_requests').get()?.result_json).toBe(
      '{}',
    );
    expect(database.prepare('PRAGMA foreign_key_check').all()).toEqual([]);
    database.prepare("DELETE FROM imports WHERE id='i'").run();
    expect(database.prepare('SELECT COUNT(*) AS n FROM conversations').get()?.n).toBe(0);
    expect(database.prepare('SELECT COUNT(*) AS n FROM generation_requests').get()?.n).toBe(0);
    expect(database.prepare('SELECT COUNT(*) AS n FROM users').get()?.n).toBe(1);
  });
});
it('settles legacy interrupted comparisons conservatively while preserving completed saved results', () => {
  const database = db();
  for (const file of files.filter((x) => x < '0015_')) migrate(database, file);
  database.exec(
    "INSERT INTO users(id,display_name,role,created_at) VALUES('u','reader','owner',1); INSERT INTO budget_days(day) VALUES('2026-10-13'); INSERT INTO user_budget_days(user_id,day) VALUES('u','2026-10-13'); INSERT INTO comparison_jobs(id,user_id,request_hash,status,saved,metrics_json,created_at,updated_at) VALUES('active','u','h','running',0,NULL,1,1),('saved','u','h','complete',1,'{\"results\":[]}',1,1); INSERT INTO budget_reservations(id,user_id,day,amount,created_at,app_limit,user_limit) VALUES('comparison:active','u','2026-10-13',100,1,1000,500)",
  );
  applyPending(database);
  expect(
    database.prepare("SELECT status,error_code FROM comparison_jobs WHERE id='active'").get(),
  ).toMatchObject({ status: 'failed', error_code: 'legacy_execution_interrupted' });
  expect(
    database.prepare("SELECT state FROM budget_reservations WHERE id='comparison:active'").get()
      ?.state,
  ).toBe('settled');
  expect(
    database.prepare("SELECT consumed FROM budget_days WHERE day='2026-10-13'").get()?.consumed,
  ).toBe(100);
  expect(
    database.prepare("SELECT status,metrics_json FROM comparison_jobs WHERE id='saved'").get(),
  ).toMatchObject({ status: 'complete', metrics_json: '{"results":[]}' });
});
