import { it, expect } from 'vitest';
import { Hono } from 'hono';
import { HTTPException } from 'hono/http-exception';
import { z } from 'zod';
import { body } from '../src/http';
import type { AppEnv } from '../src/types';
import { testEnv } from './helpers/db';
it('bounds synchronous empty request chunks independently of advancing clocks', async () => {
  const app = new Hono<AppEnv>();
  app.onError((e, c) => (e instanceof HTTPException ? e.getResponse() : c.body(null, 500)));
  app.post('/', async (c) => c.json(await body(c, z.object({}))));
  let pulls = 0,
    cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls++;
      controller.enqueue(new Uint8Array());
    },
    cancel() {
      cancelled = true;
    },
  });
  const response = await app.fetch(
    new Request('http://localhost/', {
      method: 'POST',
      body: stream,
      duplex: 'half',
    } as RequestInit),
    testEnv(),
  );
  expect(response.status).toBe(413);
  expect(cancelled).toBe(true);
  expect(pulls).toBeLessThan(70);
});
