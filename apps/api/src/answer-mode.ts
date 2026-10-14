import { z } from 'zod';
import type { Env } from './types';
import { fail } from './http';
export const answerModeSchema = z.enum(['reviewed-claim-selection', 'grounded-generation']);
export type AnswerMode = z.infer<typeof answerModeSchema>;
export const GROUNDED_POLICY_VERSION = 'grounded-generation-2026-10-13.v1';
export const GROUNDED_NOTICE_JA =
  '実験的なAI解説です。引用資料と読書範囲を検証しますが、説明の正確さや未読の出来事を暗示しないことは保証できません。本文と出典を確認してください。';
export function answerModes(env: Env): AnswerMode[] {
  if (env.ALLOWED_ANSWER_MODES === undefined) return ['reviewed-claim-selection'];
  try {
    return z.array(answerModeSchema).min(1).max(2).parse(JSON.parse(env.ALLOWED_ANSWER_MODES));
  } catch {
    return [];
  }
}
export function assertAnswerMode(env: Env, mode: AnswerMode) {
  if (!answerModes(env).includes(mode))
    fail(503, 'answer_mode_disabled', 'This answer mode is not enabled by the operator.');
}
export function hasGroundedConsent(settings: Record<string, unknown>): boolean {
  return (
    settings.groundedGenerationConsent === true &&
    settings.groundedGenerationPolicyVersion === GROUNDED_POLICY_VERSION
  );
}
/** Bind alongside the mode, never interpolate client strings into SQL. */
export const consentSQL =
  "json_extract(u.settings_json,'$.workersAiConsent')=1 AND (?='reviewed-claim-selection' OR (json_extract(u.settings_json,'$.groundedGenerationConsent')=1 AND json_extract(u.settings_json,'$.groundedGenerationPolicyVersion')=?))";
