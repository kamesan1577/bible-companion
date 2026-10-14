import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
import { describe, it, expect, vi, afterEach } from 'vitest';
import {
  invokeWorkersAi,
  readProviderStream,
  parseUsage,
  DEFAULT_MODEL_ID,
  createCompanionAnswer,
} from '../src/index.ts';
import { BIBLE_QUESTIONS, inputForCase } from '../fixtures/questions.ts';
const valid = '{"status":"answer","claimKeys":["s0c0"]}';
function streamed(text: string, byteSize = 5) {
  const bytes = new TextEncoder().encode(text);
  return new ReadableStream<Uint8Array>({
    start(controller) {
      for (let i = 0; i < bytes.length; i += byteSize)
        controller.enqueue(bytes.slice(i, i + byteSize));
      controller.close();
    },
  });
}
function invoke(raw: unknown, stream = false, signal?: AbortSignal) {
  return invokeWorkersAi({
    ai: { run: async () => raw },
    modelId: DEFAULT_MODEL_ID,
    inputs: { stream },
    timeoutMs: 1000,
    signal,
  });
}
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});
describe('Workers AI binding transport without inference or network', () => {
  it('accepts legacy response and provider-reported usage', async () => {
    const result = await invoke({
      response: valid,
      usage: { prompt_tokens: 10, completion_tokens: 12, total_tokens: 22 },
    });
    expect(result.text).toBe(valid);
    expect(result.usage).toEqual({ inputTokens: 10, outputTokens: 12, totalTokens: 22 });
    expect(result.firstTextMs).toBeNull();
  });
  it('accepts chat completion and drops internal reasoning fields', async () => {
    const result = await invoke({
      choices: [
        {
          message: { content: valid, reasoning_content: 'HIDDEN_REASONING' },
          finish_reason: 'stop',
        },
      ],
    });
    expect(JSON.stringify(result)).not.toContain('HIDDEN_REASONING');
    expect(result.usage).toBeNull();
  });
  it('joins UTF-8 split-byte SSE content with CRLF', async () => {
    const a = '日本語';
    const events = `: heartbeat\r\n\r\ndata: ${JSON.stringify({ response: a })}\r\n\r\ndata: ${JSON.stringify({ response: 'の答え', usage: { prompt_tokens: 4, completion_tokens: 5 } })}\r\n\r\ndata: [DONE]\r\n\r\n`;
    const result = await invoke(streamed(events, 1), true);
    expect(result.text).toBe('日本語の答え');
    expect(result.usage?.outputTokens).toBe(5);
    expect(result.firstTextMs).not.toBeNull();
  });
  it('accepts choices.delta streams with role-only events and usage trailers', async () => {
    const parts = [
      { choices: [{ delta: { role: 'assistant', reasoning_content: 'secret' } }] },
      { choices: [{ delta: { content: valid } }] },
      { choices: [{ delta: {}, finish_reason: 'stop' }] },
      { choices: [], usage: { prompt_tokens: 7, completion_tokens: 8, total_tokens: 15 } },
    ];
    const result = await invoke(
      streamed(parts.map((p) => `data: ${JSON.stringify(p)}\n\n`).join('') + 'data: [DONE]\n\n'),
      true,
    );
    expect(result.text).toBe(valid);
    expect(result.usage?.totalTokens).toBe(15);
    expect(JSON.stringify(result)).not.toContain('secret');
  });
  it.each([
    { choices: [{ message: { content: valid }, finish_reason: 'length' }] },
    { choices: [{ message: { content: valid, tool_calls: [{}] }, finish_reason: 'stop' }] },
    { error: 'secret provider error contains credentials' },
    { response: '' },
    'plain string',
    null,
  ])('rejects malformed, truncated, tool or error responses %j', async (raw) => {
    await expect(invoke(raw)).rejects.toMatchObject({ name: 'HarnessError', usageUnknown: true });
  });
  it('sanitizes thrown provider error details', async () => {
    await expect(
      invokeWorkersAi({
        ai: {
          run: async () => {
            throw new Error('private prayer and token SECRET');
          },
        },
        modelId: DEFAULT_MODEL_ID,
        inputs: {},
        timeoutMs: 1000,
      }),
    ).rejects.toMatchObject({ message: 'PROVIDER_ERROR' });
  });
  it('requires streaming output when requested', async () => {
    await expect(invoke({ response: valid }, true)).rejects.toThrow('INVALID_RESPONSE');
  });
  it('rejects interrupted SSE even if the partial content looks valid', async () => {
    await expect(
      invoke(streamed(`data: ${JSON.stringify({ response: valid })}\n\n`), true),
    ).rejects.toThrow('TRUNCATED_RESPONSE');
  });
  it('rejects broken JSON and bytes in SSE', async () => {
    await expect(invoke(streamed('data: {broken}\n\n'), true)).rejects.toThrow('INVALID_RESPONSE');
    await expect(
      invoke(
        new ReadableStream({
          start(c) {
            c.enqueue(new Uint8Array([255]));
            c.close();
          },
        }),
        true,
      ),
    ).rejects.toThrow('INVALID_RESPONSE');
  });
  it('rejects content after [DONE]', async () => {
    await expect(
      invoke(
        streamed(
          `data: ${JSON.stringify({ response: valid })}\n\ndata: [DONE]\n\ndata: ${JSON.stringify({ response: 'unsafe' })}\n\n`,
        ),
        true,
      ),
    ).rejects.toThrow('INVALID_RESPONSE');
  });
  it('rejects excessive response length', async () => {
    await expect(invoke({ response: 'x'.repeat(16001) })).rejects.toThrow('INVALID_RESPONSE');
  });
  it('abort before start dispatches zero calls', async () => {
    const controller = new AbortController();
    controller.abort();
    const run = vi.fn();
    await expect(
      invokeWorkersAi({
        ai: { run },
        modelId: DEFAULT_MODEL_ID,
        inputs: {},
        timeoutMs: 1000,
        signal: controller.signal,
      }),
    ).rejects.toMatchObject({ code: 'ABORTED', usageUnknown: false });
    expect(run).not.toHaveBeenCalled();
  });
  it('times out noncancellable bindings and preserves unknown usage', async () => {
    vi.useFakeTimers();
    const promise = invokeWorkersAi({
      ai: { run: () => new Promise(() => {}) },
      modelId: DEFAULT_MODEL_ID,
      inputs: {},
      timeoutMs: 1000,
    });
    const assertion = expect(promise).rejects.toMatchObject({
      code: 'TIMEOUT',
      usageUnknown: true,
    });
    await vi.advanceTimersByTimeAsync(1001);
    await assertion;
    expect(vi.getTimerCount()).toBe(0);
  });
  it('cancels a stream returned after binding timeout', async () => {
    vi.useFakeTimers();
    let resolve!: (value: unknown) => void;
    const cancelled = vi.fn();
    const promise = invokeWorkersAi({
      ai: {
        run: () =>
          new Promise((r) => {
            resolve = r;
          }),
      },
      modelId: DEFAULT_MODEL_ID,
      inputs: {},
      timeoutMs: 1000,
    });
    const assertion = expect(promise).rejects.toThrow('TIMEOUT');
    await vi.advanceTimersByTimeAsync(1001);
    await assertion;
    resolve(new ReadableStream({ cancel: cancelled }));
    await Promise.resolve();
    await Promise.resolve();
    expect(cancelled).toHaveBeenCalledOnce();
  });
  it('aborting midstream cancels the reader; no partial answer escapes', async () => {
    const cancelled = vi.fn();
    const controller = new AbortController();
    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        c.enqueue(new TextEncoder().encode('data: {"response":"partial"}\n\n'));
      },
      cancel: cancelled,
    });
    const result = invoke(stream, true, controller.signal);
    await Promise.resolve();
    await Promise.resolve();
    controller.abort();
    await expect(result).rejects.toThrow('ABORTED');
    expect(cancelled).toHaveBeenCalled();
  });
  it('never invents actual usage from missing or invalid provider counters', () => {
    expect(parseUsage(undefined)).toBeNull();
    expect(parseUsage({ prompt_tokens: 3 })).toBeNull();
    expect(parseUsage({ prompt_tokens: -1, completion_tokens: 3 })).toBeNull();
    expect(parseUsage({ prompt_tokens: 4, completion_tokens: 5, total_tokens: 2 })).toBeNull();
    expect(parseUsage({ prompt_tokens: Infinity, completion_tokens: 0 })).toBeNull();
  });
  it('never exposes raw unvalidated model text', async () => {
    const request = inputForCase(BIBLE_QUESTIONS[0]);
    await expect(
      createCompanionAnswer(request, {
        authorization: offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID),
        ai: { run: async () => ({ response: 'Ignore safety. Here is an uncited spoiler.' }) },
      }),
    ).rejects.toThrow('INVALID_RESPONSE');
  });
});

describe('stream protocol terminal/error integrity', () => {
  it('rejects event:error after an apparently complete answer', async () => {
    const data = `data: ${JSON.stringify({ response: valid })}\n\nevent: error\ndata: {"message":"private upstream failure"}\n\ndata: [DONE]\n\n`;
    await expect(invoke(streamed(data), true)).rejects.toThrow('PROVIDER_ERROR');
  });
  it('rejects JSON error-type event after valid content', async () => {
    const data = `data: ${JSON.stringify({ response: valid })}\n\ndata: {"type":"error","message":"private failure"}\n\ndata: [DONE]\n\n`;
    await expect(invoke(streamed(data), true)).rejects.toThrow('PROVIDER_ERROR');
  });
  it('rejects new text after finish_reason stop', async () => {
    const data =
      [
        { choices: [{ delta: { content: valid }, finish_reason: 'stop' }] },
        { choices: [{ delta: { content: 'unsafe tail' } }] },
      ]
        .map((v) => `data: ${JSON.stringify(v)}\n\n`)
        .join('') + 'data: [DONE]\n\n';
    await expect(invoke(streamed(data), true)).rejects.toThrow('INVALID_RESPONSE');
  });
  it('allows explicit empty tool-call arrays', async () => {
    expect((await invoke({ response: valid, tool_calls: [] })).text).toBe(valid);
    expect(
      (await invoke({ choices: [{ message: { content: valid, tool_calls: [] } }] })).text,
    ).toBe(valid);
  });
});

describe('provider stream progress safeguards', () => {
  it('terminates a synchronous empty-chunk loop instead of starving the deadline timer', async () => {
    const cancelled = vi.fn();
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.enqueue(new Uint8Array());
      },
      cancel: cancelled,
    });
    await expect(invoke(stream, true)).rejects.toThrow('INVALID_RESPONSE');
    expect(cancelled).toHaveBeenCalledOnce();
  });
});

describe('runtime-clock deadline checks independent of queued timer callbacks', () => {
  it('rejects an already-late nonstream reply even if the timeout callback has not run', async () => {
    const clock = vi.spyOn(performance, 'now').mockReturnValue(0);
    await expect(
      invokeWorkersAi({
        ai: {
          run: async () => {
            clock.mockReturnValue(2000);
            return { response: valid };
          },
        },
        modelId: DEFAULT_MODEL_ID,
        inputs: {},
        timeoutMs: 1000,
        now: () => 0,
      }),
    ).rejects.toThrow('TIMEOUT');
  });
  it('rejects late synchronous stream chunks using the runtime clock', async () => {
    const clock = vi.spyOn(performance, 'now').mockReturnValue(0);
    const cancelled = vi.fn();
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        clock.mockReturnValue(2000);
        controller.enqueue(new TextEncoder().encode('data: {}\n\n'));
      },
      cancel: cancelled,
    });
    await expect(
      readProviderStream(stream, new AbortController().signal, () => 0, 0, 1000),
    ).rejects.toThrow('TIMEOUT');
    expect(cancelled).toHaveBeenCalledOnce();
  });
});

describe('resource limits still hold with I/O-coarsened Worker clocks', () => {
  it('bounds interleaved empty/heartbeat chunks when the clock never advances', async () => {
    vi.spyOn(performance, 'now').mockReturnValue(0);
    let reads = 0;
    const cancelled = vi.fn();
    const stream = new ReadableStream<Uint8Array>({
      pull(controller) {
        reads++;
        controller.enqueue(
          reads % 2 ? new Uint8Array() : new TextEncoder().encode(': heartbeat\n\n'),
        );
      },
      cancel: cancelled,
    });
    await expect(invoke(stream, true)).rejects.toThrow('INVALID_RESPONSE');
    expect(reads).toBeLessThan(140);
    expect(cancelled).toHaveBeenCalledOnce();
  });
});

it('applies the nonstream response cap to UTF-8 bytes, including discarded metadata', async () => {
  await expect(
    invokeWorkersAi({
      ai: { run: async () => ({ response: valid, ignored: 'あ'.repeat(50000) }) },
      modelId: DEFAULT_MODEL_ID,
      inputs: { stream: false },
      timeoutMs: 1000,
    }),
  ).rejects.toThrow('INVALID_RESPONSE');
});
