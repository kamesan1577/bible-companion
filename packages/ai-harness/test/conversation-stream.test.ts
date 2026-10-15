import { describe, it, expect } from 'vitest';
import { ACTS_SOURCES } from '../fixtures/acts-sources';
import { offlineFixtureAuthorization } from '../fixtures/authorization';
import {
  createCompanionAnswer,
  prepareCompanionRequest,
  DEFAULT_MODEL_ID,
  scopedHistory,
} from '../src/index';
import { validatedPreview } from '../src/stream-preview';
import { questionContextWindow } from '../../core/src/index';
import type { GroundingSource } from '../src/types';
const passage = { book: 'ACT', start: { chapter: 24, verse: 23 }, end: { chapter: 24, verse: 24 } };
const source: GroundingSource = {
  ...ACTS_SOURCES[0],
  id: 'felix-fixture',
  start: { chapter: 23, verse: 24 },
  end: { chapter: 23, verse: 24 },
  spoilerEnd: { chapter: 23, verse: 24 },
  text: 'Bring Paul safely to Felix the governor.',
  claims: [],
};
const claim = {
  text: 'フェリクスは、パウロが引き渡された総督です。',
  kind: 'fact',
  sourceId: source.id,
  evidenceQuote: 'Felix the governor',
};
const scope = { passage, spoilerAllowed: false, sourceIds: [], sourceVersions: {} };
describe('screenshot question regressions and observed streaming', () => {
  it.each(['誰やねんペリクスって', 'ペリクスってだれは'])(
    'forwards latest identity question and privately scoped history: %s',
    async (question) => {
      const input = {
        passage,
        question,
        spoilerAllowed: false,
        sources: [source],
        history: [
          { role: 'user' as const, content: '初めて読むので教えて', ownerId: 'alice', scope },
        ],
        settings: { stream: true },
      };
      const stages: string[] = [];
      const previews: string[] = [];
      const result = await createCompanionAnswer(input, {
        authorization: offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID),
        answerMode: 'grounded-generation',
        onProgress: async (s) => {
          stages.push(s);
        },
        onPreview: async (s) => {
          previews.push(s);
        },
        ai: {
          async run(model, settings) {
            expect(model).toBe(DEFAULT_MODEL_ID);
            expect(settings.stream).toBe(true);
            expect(settings.chat_template_kwargs).toEqual({ enable_thinking: false });
            const messages = settings.messages as { content: string }[];
            const data = JSON.parse(messages[1].content);
            expect(data.question).toBe(question);
            expect(data.history[0].content).toBe('初めて読むので教えて');
            expect(data.sources[0].text).toContain('governor');
            expect(messages[0].content).toContain('身元・立場・役割を先に');
            const raw = JSON.stringify({ status: 'answer', claims: [claim] });
            const chunks = [raw.slice(0, -2), raw.slice(-2)];
            return new ReadableStream({
              start(c) {
                for (const response of chunks)
                  c.enqueue(
                    new TextEncoder().encode('data: ' + JSON.stringify({ response }) + '\n\n'),
                  );
                c.enqueue(new TextEncoder().encode('data: [DONE]\n\n'));
                c.close();
              },
            });
          },
        },
      });
      expect(result.answer).toContain('総督');
      expect(previews).toEqual([claim.text]);
      expect(stages).toEqual(['receiving', 'validating']);
      expect(result.timing.streamed).toBe(true);
    },
  );
  it('never previews incomplete quotes, unrecognized sources or raw reasoning', () => {
    const raw = JSON.stringify({ status: 'answer', claims: [claim] });
    expect(validatedPreview(raw.slice(0, -3), [source], passage, false)).toBeNull();
    expect(validatedPreview(raw, [], passage, false)).toBeNull();
    expect(validatedPreview('reasoning secret ' + raw, [source], passage, false)).toBeNull();
    expect(validatedPreview(raw, [source], passage, false)).toBe(claim.text);
  });
  it('adds earlier context with a hard 32-verse bound while retaining the spoiler end', () => {
    const window = questionContextWindow(passage, passage, true);
    expect(window.start).toEqual({ chapter: 23, verse: 34 });
    expect(window.end).toEqual(passage.end);
    expect(questionContextWindow(passage, passage).start).toEqual(passage.start);
  });
  it('only retains uncited general knowledge history under explicit policy and correct owner', () => {
    const input = {
      passage,
      question: 'それは誰？',
      spoilerAllowed: false,
      sources: [source],
      history: [
        { role: 'assistant' as const, content: '出典未確認の背景', ownerId: 'alice', scope },
      ],
    };
    expect(scopedHistory(input, [source], 'alice')).toHaveLength(0);
    expect(scopedHistory(input, [source], 'alice', true)).toHaveLength(1);
    expect(scopedHistory(input, [source], 'bob', true)).toHaveLength(0);
    const request = prepareCompanionRequest(input, {
      authorization: offlineFixtureAuthorization('alice', DEFAULT_MODEL_ID),
      answerMode: 'grounded-generation',
      allowGeneralKnowledge: true,
    });
    expect(request.history).toHaveLength(1);
    expect(request.messages[0].content).not.toContain('根拠がない場合は不足と答えます。');
    expect(request.messages[0].content).toContain('出典未確認の説明を分けます');
  });
});
