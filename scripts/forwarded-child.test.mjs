import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { runForwardedChild } from './forwarded-child.mjs';
test('local CLI preserves the actual child exit code and removes listeners', async () => {
  const parent = new EventEmitter();
  const result = await runForwardedChild(
    process.execPath,
    ['-e', 'process.exit(7)'],
    { stdio: 'ignore' },
    parent,
  );
  assert.equal(result.code, 7);
  assert.equal(parent.listenerCount('SIGTERM'), 0);
});
test(
  'local CLI forwards cancellation and waits for the child to close',
  { timeout: 5000 },
  async () => {
    const parent = new EventEmitter();
    const promise = runForwardedChild(
      process.execPath,
      ['-e', 'setInterval(()=>{},1000)'],
      { stdio: 'ignore' },
      parent,
    );
    parent.emit('SIGTERM');
    const result = await promise;
    assert.equal(result.signal, 'SIGTERM');
    assert.equal(parent.listenerCount('SIGTERM'), 0);
    assert.equal(parent.listenerCount('SIGINT'), 0);
  },
);
test(
  'cancellation stays a failed result even if a CLI launcher reports exit zero after termination',
  { timeout: 5000 },
  async (t) => {
    const { mkdtempSync, existsSync, rmSync } = await import('node:fs');
    const { tmpdir } = await import('node:os');
    const { join } = await import('node:path');
    const { setTimeout: delay } = await import('node:timers/promises');
    const directory = mkdtempSync(join(tmpdir(), 'forwarded-signal-'));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const ready = join(directory, 'ready');
    const parent = new EventEmitter();
    const pending = runForwardedChild(
      process.execPath,
      [
        '-e',
        `process.on('SIGTERM',()=>process.exit(0));require('node:fs').writeFileSync(${JSON.stringify(ready)},'ready');setInterval(()=>{},1000);`,
      ],
      { stdio: 'ignore' },
      parent,
    );
    for (let i = 0; i < 100 && !existsSync(ready); i++) await delay(10);
    assert(existsSync(ready));
    parent.emit('SIGTERM');
    const result = await pending;
    assert.equal(result.code, null);
    assert.equal(result.signal, 'SIGTERM');
  },
);
