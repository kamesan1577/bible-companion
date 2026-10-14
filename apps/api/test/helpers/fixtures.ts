import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const fixtures = fileURLToPath(new URL('../../../../docs/fixtures/', import.meta.url));
function sanitize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sanitize);
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.entries(value).map(([key, val]) => [
        key,
        ['createdAt', 'expiresAt', 'checkedAt', 'leaseExpiresAt', 'lastMessageAt'].includes(key) &&
        typeof val === 'number'
          ? 1791907200 + (key === 'expiresAt' ? 900 : key === 'leaseExpiresAt' ? 90 : 0)
          : key === 'timing' && val && typeof val === 'object'
            ? Object.fromEntries(
                Object.entries(val).map(([name, measurement]) => [
                  name,
                  typeof measurement === 'number' ? 1 : measurement,
                ]),
              )
            : sanitize(val),
      ]),
    );
  if (typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f-]{27}$/.test(value))
    return '00000000-0000-4000-8000-000000000001';
  return value;
}
export function fixture(name: string, value: unknown) {
  if (process.env.UPDATE_API_FIXTURES === '1') {
    mkdirSync(fixtures, { recursive: true });
    const normalized = sanitize(value) as Record<string, unknown>;
    if (
      name === 'conversation-detail' &&
      Array.isArray((value as { messages?: unknown[] }).messages)
    ) {
      const original = value as { messages: { id: string }[]; nextMessageCursor: string | null };
      const ids = new Map(
        original.messages.map((message, index) => [
          message.id,
          '00000000-0000-4000-8000-' + String(index + 100).padStart(12, '0'),
        ]),
      );
      const messages = normalized.messages as { id: string }[];
      original.messages.forEach((message, index) => {
        messages[index].id = ids.get(message.id)!;
      });
      if (original.nextMessageCursor)
        normalized.nextMessageCursor =
          ids.get(original.nextMessageCursor) ?? original.nextMessageCursor;
    }
    writeFileSync(fixtures + name + '.json', JSON.stringify(normalized, null, 2) + '\n');
  }
}
