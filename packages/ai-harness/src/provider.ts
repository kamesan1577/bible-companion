import { HarnessError } from './errors.ts';
import { isRecord } from './grounding.ts';
import type { UsageReport, WorkersAiBinding } from './types.ts';
export interface ProviderResponse {
  text: string;
  usage: UsageReport['actual'];
  firstTextMs: number | null;
  streamed: boolean;
}
const MAX_RESPONSE_BYTES = 128 * 1024;
const MAX_TEXT_CHARS = 16000;
export function parseUsage(value: unknown): UsageReport['actual'] {
  if (!isRecord(value)) return null;
  const input = value.prompt_tokens ?? value.input_tokens;
  const output = value.completion_tokens ?? value.output_tokens;
  const total = value.total_tokens;
  const valid = (n: unknown): n is number =>
    typeof n === 'number' && Number.isSafeInteger(n) && n >= 0;
  if (
    !valid(input) ||
    !valid(output) ||
    (total !== undefined && (!valid(total) || total < input + output))
  )
    return null;
  return {
    inputTokens: input,
    outputTokens: output,
    ...(total === undefined ? {} : { totalTokens: total as number }),
  };
}
function isStream(value: unknown): value is ReadableStream<Uint8Array> {
  return (
    value !== null &&
    typeof value === 'object' &&
    typeof (value as ReadableStream).getReader === 'function'
  );
}
function unwrap(
  value: unknown,
  streaming = false,
): { text: string; usage: UsageReport['actual']; finished: boolean } {
  if (
    !isRecord(value) ||
    value.error ||
    value.errors ||
    value.success === false ||
    value.type === 'error'
  )
    throw new HarnessError('PROVIDER_ERROR', true);
  let text = '';
  let finished = false;
  if (Array.isArray(value.choices)) {
    if (value.choices.length > 1) throw new HarnessError('INVALID_RESPONSE', true);
    const choice = value.choices[0];
    if (choice !== undefined) {
      if (!isRecord(choice)) throw new HarnessError('INVALID_RESPONSE', true);
      if (choice.finish_reason === 'length') throw new HarnessError('TRUNCATED_RESPONSE', true);
      if (choice.finish_reason && choice.finish_reason !== 'stop')
        throw new HarnessError('INVALID_RESPONSE', true);
      finished = choice.finish_reason === 'stop';
      const message = choice[streaming ? 'delta' : 'message'];
      if (message !== undefined) {
        if (
          !isRecord(message) ||
          (message.tool_calls != null &&
            (!Array.isArray(message.tool_calls) || message.tool_calls.length > 0)) ||
          message.function_call ||
          message.refusal
        )
          throw new HarnessError('INVALID_RESPONSE', true);
        if (typeof message.content === 'string') text = message.content;
        else if (message.content !== null && message.content !== undefined)
          throw new HarnessError('INVALID_RESPONSE', true);
        // reasoning_content and other internal reasoning fields are intentionally never surfaced.
      }
    }
  } else if (typeof value.response === 'string') {
    if (
      value.tool_calls != null &&
      (!Array.isArray(value.tool_calls) || value.tool_calls.length > 0)
    )
      throw new HarnessError('INVALID_RESPONSE', true);
    text = value.response;
  } else if (!streaming) {
    throw new HarnessError('INVALID_RESPONSE', true);
  }
  return { text, usage: parseUsage(value.usage), finished };
}
function abortError(signal: AbortSignal): HarnessError {
  return signal.reason instanceof HarnessError ? signal.reason : new HarnessError('ABORTED', true);
}
async function raceAbort<T>(promise: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) throw abortError(signal);
  let onAbort: () => void = () => {};
  const aborted = new Promise<never>((_, reject) => {
    onAbort = () => reject(abortError(signal));
    signal.addEventListener('abort', onAbort, { once: true });
  });
  try {
    return await Promise.race([promise, aborted]);
  } finally {
    signal.removeEventListener('abort', onAbort);
  }
}
/** Parse fragmented SSE privately. Never emit an unvalidated delta to a caller or logger. */
export async function readProviderStream(
  stream: ReadableStream<Uint8Array>,
  signal: AbortSignal,
  now: () => number,
  startedAt: number,
  deadlineAt = performance.now() + 15000,
): Promise<ProviderResponse> {
  const reader = stream.getReader();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let buffer = '';
  let text = '';
  let totalBytes = 0;
  let emptyChunkReads = 0;
  let chunkReads = 0;
  let firstTextMs: number | null = null;
  let usage: UsageReport['actual'] = null;
  let doneMarker = false;
  let finished = false;
  let successful = false;
  const cancel = () => {
    void reader.cancel().catch(() => {});
  };
  signal.addEventListener('abort', cancel, { once: true });
  function consume(event: string) {
    if (doneMarker) {
      if (event.trim()) throw new HarnessError('INVALID_RESPONSE', true);
      return;
    }
    if (event.split('\n').some((line) => /^event:\s*error\s*$/.test(line)))
      throw new HarnessError('PROVIDER_ERROR', true);
    const data = event
      .split('\n')
      .filter((line) => line.startsWith('data:'))
      .map((line) => line.slice(5).replace(/^ /, ''))
      .join('\n');
    if (!data) return; // Comments and heartbeat events are not text or TTFT.
    if (data.trim() === '[DONE]') {
      doneMarker = true;
      return;
    }
    let value: unknown;
    try {
      value = JSON.parse(data);
    } catch {
      throw new HarnessError('INVALID_RESPONSE', true);
    }
    const part = unwrap(value, true);
    if (finished && part.text) throw new HarnessError('INVALID_RESPONSE', true);
    if (part.usage) usage = part.usage;
    if (part.finished) finished = true;
    if (part.text) {
      if (firstTextMs === null) firstTextMs = Math.max(0, now() - startedAt);
      text += part.text;
      if (text.length > MAX_TEXT_CHARS) throw new HarnessError('INVALID_RESPONSE', true);
    }
  }
  try {
    while (true) {
      if (++chunkReads > 8192) throw new HarnessError('INVALID_RESPONSE', true);
      const chunk = await raceAbort(reader.read(), signal);
      if (performance.now() >= deadlineAt) throw new HarnessError('TIMEOUT', true);
      if (signal.aborted) throw abortError(signal);
      if (chunk.done) break;
      if (!(chunk.value instanceof Uint8Array)) throw new HarnessError('INVALID_RESPONSE', true);
      // A broken stream that synchronously emits empty chunks must not starve the deadline timer.
      if (chunk.value.byteLength === 0) {
        if (++emptyChunkReads >= 64) throw new HarnessError('INVALID_RESPONSE', true);
        continue;
      }
      totalBytes += chunk.value.byteLength;
      if (totalBytes > MAX_RESPONSE_BYTES) throw new HarnessError('INVALID_RESPONSE', true);
      buffer += decoder.decode(chunk.value, { stream: true });
      // Normalize complete CRLF pairs, retaining a trailing CR split across chunks.
      buffer = buffer.replace(/\r\n/g, '\n');
      let boundary: number;
      while ((boundary = buffer.indexOf('\n\n')) !== -1) {
        consume(buffer.slice(0, boundary));
        buffer = buffer.slice(boundary + 2);
      }
    }
    buffer += decoder.decode();
    if (buffer.trim()) consume(buffer.replace(/\r\n/g, '\n'));
    if (!doneMarker && !finished) throw new HarnessError('TRUNCATED_RESPONSE', true);
    if (!text.trim()) throw new HarnessError('INVALID_RESPONSE', true);
    successful = true;
    return { text, usage, firstTextMs, streamed: true };
  } catch (error) {
    if (error instanceof HarnessError) throw error;
    throw new HarnessError('INVALID_RESPONSE', true);
  } finally {
    signal.removeEventListener('abort', cancel);
    if (!successful) {
      void reader.cancel().catch(() => {});
    }
    reader.releaseLock();
  }
}
export async function invokeWorkersAi(options: {
  ai: WorkersAiBinding;
  modelId: string;
  inputs: Record<string, unknown>;
  timeoutMs: number;
  signal?: AbortSignal;
  now?: () => number;
}): Promise<ProviderResponse> {
  // Deadlines use the runtime clock, never the optional telemetry clock.
  // Workers clocks advance only after I/O; byte/chunk limits separately bound synchronous parsing.
  const deadlineAt = performance.now() + options.timeoutMs;
  const now = options.now ?? (() => performance.now());
  const startedAt = now();
  if (options.signal?.aborted) throw new HarnessError('ABORTED', false);
  const controller = new AbortController();
  const onAbort = () => controller.abort(new HarnessError('ABORTED', true));
  options.signal?.addEventListener('abort', onAbort, { once: true });
  const timer = setTimeout(
    () => controller.abort(new HarnessError('TIMEOUT', true)),
    options.timeoutMs,
  );
  let rawPromise: Promise<unknown> | undefined;
  try {
    // AI.run currently has no documented AbortSignal parameter. Don't pass a fake one.
    rawPromise = Promise.resolve().then(() => {
      if (controller.signal.aborted) throw abortError(controller.signal);
      return options.ai.run(options.modelId, options.inputs);
    });
    // If AI.run returns a stream after abandonment, cancel the stream rather than leaking it.
    void rawPromise.then(
      (raw) => {
        if (controller.signal.aborted && isStream(raw)) void raw.cancel().catch(() => {});
      },
      () => {},
    );
    const raw = await raceAbort(rawPromise, controller.signal);
    if (performance.now() >= deadlineAt) {
      controller.abort(new HarnessError('TIMEOUT', true));
      if (isStream(raw)) void raw.cancel().catch(() => {});
      throw abortError(controller.signal);
    }
    if (controller.signal.aborted) throw abortError(controller.signal);
    if (isStream(raw))
      return await readProviderStream(raw, controller.signal, now, startedAt, deadlineAt);
    if (options.inputs.stream === true) throw new HarnessError('INVALID_RESPONSE', true);
    const serialized = JSON.stringify(raw);
    if (
      serialized === undefined ||
      new TextEncoder().encode(serialized).byteLength > MAX_RESPONSE_BYTES
    )
      throw new HarnessError('INVALID_RESPONSE', true);
    const response = unwrap(raw);
    if (!response.text.trim() || response.text.length > MAX_TEXT_CHARS)
      throw new HarnessError('INVALID_RESPONSE', true);
    return { text: response.text, usage: response.usage, firstTextMs: null, streamed: false };
  } catch (error) {
    if (error instanceof HarnessError) throw error;
    throw new HarnessError('PROVIDER_ERROR', true);
  } finally {
    clearTimeout(timer);
    options.signal?.removeEventListener('abort', onAbort);
  }
}
