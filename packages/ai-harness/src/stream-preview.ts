import { validateGeneratedAnswer } from './output.ts';
import type { GroundingSource, Passage } from './types.ts';

/** Only complete, individually citation-validated claims. No raw tokens, reasoning or general knowledge.
 * Preview is provisional: the full document and current policy still have to pass before persistence.
 */
export function validatedPreview(
  raw: string,
  sources: readonly GroundingSource[],
  boundary: Passage,
  spoilers: boolean,
): string | null {
  const prefix = raw.match(/^\s*\{\s*"status"\s*:\s*"answer"\s*,\s*"claims"\s*:\s*\[/);
  if (!prefix) return null;
  const claims: unknown[] = [];
  let start = -1,
    depth = 0,
    quoted = false,
    escaped = false;
  for (let i = prefix[0].length; i < raw.length; i++) {
    const char = raw[i];
    if (quoted) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if (char === '"') quoted = false;
      continue;
    }
    if (char === '"') {
      if (!depth) return null;
      quoted = true;
    } else if (char === '{' || char === '[') {
      if (!depth) {
        if (char !== '{') return null;
        start = i;
      }
      depth++;
    } else if (char === '}' || char === ']') {
      if (!depth) break;
      depth--;
      if (!depth) {
        try {
          claims.push(JSON.parse(raw.slice(start, i + 1)));
        } catch {
          return null;
        }
        if (claims.length > 3) return null;
      }
    } else if (!depth && !/[\s,]/.test(char)) return null;
  }
  if (!claims.length) return null;
  try {
    return validateGeneratedAnswer(
      JSON.stringify({ status: 'answer', claims }),
      sources,
      boundary,
      spoilers,
    ).answer;
  } catch {
    return null;
  }
}
