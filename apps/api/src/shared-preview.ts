import { Hono } from 'hono';
import { z } from 'zod';
import { parseImport } from '@bible/core';
import { createSourceOnlyAnswer } from '@bible/ai-harness';
import { body, fail } from './http';
import { getSources, sourcePolicyVersion } from './data';
import { rateLimit } from './budget';
import type { AppEnv } from './types';
export const sharedPreview = new Hono<AppEnv>();
// Only curated public references. No session, private imports, history or AI invocation.
sharedPreview.post('/reading-preview', async (c) => {
  await rateLimit(c.env, 'public-preview:' + (c.req.header('CF-Connecting-IP') ?? 'local'), 20);
  const input = await body(c, z.object({ sharedText: z.string().min(1).max(20000) }).strict());
  let parsed;
  try {
    parsed = parseImport(input.sharedText);
    if (!parsed.ranges.length) {
      const parts = input.sharedText.split(/\n/).filter((line) => line.trim());
      const candidates = parts.map((part) => parseImport(part));
      const ranges = [...new Map(candidates.flatMap((part) => part.ranges).map((range) => [JSON.stringify(range), range])).values()];
      const translations = [...new Set(candidates.flatMap((part) => part.translation ? [part.translation] : []))];
      parsed = { ...parsed, ranges, translation: translations.length === 1 ? translations[0] : null };
    }
    if (!parsed.ranges.length) throw Error('No passage');
  } catch { fail(400, 'invalid_passage', '章節を読み取れませんでした。'); }
  if (parsed.ranges.length > 20) fail(400, 'too_many_ranges', '章節が多すぎます。');
  const version = await sourcePolicyVersion(c.env);
  const items = [];
  for (const passage of parsed.ranges) {
    const sources = await getSources(c.env, passage, false);
    const overview = createSourceOnlyAnswer({ passage, translation: parsed.translation ?? undefined, question: '選択箇所の確認済み資料を示してください。', spoilerAllowed: false, sources, modelId: c.env.DEFAULT_MODEL_ID }, 'public-data-only');
    items.push({ passage, text: overview.answer, citations: overview.citations });
  }
  if (version !== await sourcePolicyVersion(c.env)) fail(409, 'source_policy_changed', '資料が更新されました。再試行してください。');
  return c.json({ items, notice: '確認済みの公開資料です。AIによる生成ではありません。', translation: parsed.translation ?? null });
});
