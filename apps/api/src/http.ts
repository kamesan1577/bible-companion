import { HTTPException } from 'hono/http-exception';
import type { Context } from 'hono';
import type { z } from 'zod';
import type { AppEnv } from './types';
export function fail(
  status: 400 | 401 | 403 | 404 | 409 | 413 | 429 | 503,
  code: string,
  message: string,
): never {
  throw new HTTPException(status, {
    res: Response.json(
      { error: { code, message } },
      { status, headers: { 'Cache-Control': 'no-store' } },
    ),
  });
}
export async function body<T>(c: Context<AppEnv>, schema: z.ZodType<T>): Promise<T> {
  const length = Number(c.req.header('content-length') ?? 0);
  if (length > 65536) fail(413, 'body_too_large', 'Request exceeds 64 KiB');
  let parsed: unknown;
  try {
    const reader = c.req.raw.body?.getReader();
    if (!reader) fail(400, 'invalid_json', 'Expected JSON');
    let size = 0;
    let chunksRead = 0,
      consecutiveEmpty = 0;
    const chunks: Uint8Array[] = [];
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      chunksRead++;
      consecutiveEmpty = value.byteLength === 0 ? consecutiveEmpty + 1 : 0;
      if (chunksRead > 4096 || consecutiveEmpty > 64) {
        await reader.cancel();
        fail(413, 'body_too_fragmented', 'Request stream exceeds bounded framing limits');
      }
      size += value.byteLength;
      if (size > 65536) {
        await reader.cancel();
        fail(413, 'body_too_large', 'Request exceeds 64 KiB');
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch (e) {
    if (e instanceof HTTPException) throw e;
    fail(400, 'invalid_json', 'Expected JSON');
  }
  const result = schema.safeParse(parsed);
  if (!result.success) fail(400, 'validation_error', 'Invalid request fields');
  return result.data;
}
export function canDebug(env: AppEnv['Bindings'], user: AppEnv['Variables']['user']): boolean {
  try {
    const ids: unknown = JSON.parse(env.DEBUG_ACCOUNT_IDS ?? '[]');
    return user.role === 'owner' && Array.isArray(ids) && ids.every((id) => typeof id === 'string') && ids.includes(user.id);
  } catch { return false; }
}
export function requireDebugger(c: Context<AppEnv>): void {
  if (!canDebug(c.env, c.get('user'))) fail(403, 'debug_account_required', 'Developer access is not enabled for this account');
}
export const now = () => Math.floor(Date.now() / 1000);
export function configuredBudget(value: string): number {
  if (!/^[1-9][0-9]{0,8}$/.test(value))
    fail(
      503,
      'budget_configuration_invalid',
      'Generation is unavailable because its budget configuration is invalid.',
    );
  return Number(value);
}
