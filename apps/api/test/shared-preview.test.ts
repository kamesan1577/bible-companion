import { describe, it, expect } from 'vitest';
import { app } from '../src/index';
import { testEnv, TestDatabase } from './helpers/db';
const preview = (env: ReturnType<typeof testEnv>, sharedText: string) => app.request('/public/reading-preview', {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({sharedText})},env);
describe('anonymous shared public references', () => {
  it('returns all ranges including chapter crossings without private history or AI', async () => {
    const db = new TestDatabase(); const env = testEnv(db);
    env.AI_ENABLED = 'true'; let calls=0; env.AI={run:async()=>{calls++;throw Error('must not run');}};
    const response = await preview(env, '使徒18:18-19:2 JCB');
    expect(response.status).toBe(200);
    const result = await response.json() as {items:{passage:{start:{chapter:number};end:{chapter:number}};text:string}[]};
    expect(result.items[0].passage.start.chapter).toBe(18);
    expect(result.items[0].passage.end.chapter).toBe(19);
    expect(calls).toBe(0);
    expect(db.sqlite.prepare('SELECT count(*) AS n FROM imports').get()?.n).toBe(0);
    expect(db.sqlite.prepare('SELECT count(*) AS n FROM users').get()?.n).toBe(0);
    expect(response.headers.get('Cache-Control')).toBe('no-store');
  });
  it('does not truncate multiple references and rejects invalid ranges', async () => {
    const env=testEnv();
    const res=await preview(env,'使徒18:18 JCB\n使徒18:24-26 JCB');
    expect(res.status).toBe(200);
    expect(((await res.json()) as {items:unknown[]}).items).toHaveLength(2);
    expect((await preview(env,'使徒18:99')).status).toBe(400);
    expect((await preview(env,'x'.repeat(20001))).status).toBe(400);
  });
});
