import { MODEL_TERMS_POLICY_VERSION } from '../src/model-terms.ts';
import type { ModelAuthorization } from '../src/types.ts';
/** Synthetic test scaffolding only: no actual connection, legal review, acceptance or spending approval. */
export function offlineFixtureAuthorization(ownerId: string, modelId: string): ModelAuthorization {
  return {
    ownerId,
    connectedModelIds: [modelId],
    paidModelIds: [modelId],
    termsReviewedModelIds: [modelId],
    termsReviewVersion: MODEL_TERMS_POLICY_VERSION,
  };
}
