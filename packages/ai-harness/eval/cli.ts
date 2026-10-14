#!/usr/bin/env node
import { offlineFixtureAuthorization } from '../fixtures/authorization.ts';
import {
  createCompanionAnswer,
  prepareCompanionRequest,
  eligibleClaims,
  HarnessError,
} from '../src/index.ts';
import { BIBLE_QUESTIONS, inputForCase } from '../fixtures/questions.ts';
import { createEvaluationPlan } from './plan.ts';
import type { EvaluationPlan } from './plan.ts';
const args: string[] = process.argv.slice(2);
const option = (name: string) =>
  args.find((arg) => arg.startsWith(`${name}=`))?.slice(name.length + 1);
const recognized =
  /^(?:--offline|--plan|--help|--live|--models=.+|--questions=\d+|--repetitions=\d+|--mode=(?:reviewed-claim-selection|grounded-generation))$/;
if (args.some((arg) => !recognized.test(arg))) {
  process.stderr.write('Unsupported argument. Use --help.\n');
  process.exitCode = 2;
} else if (args.includes('--help') || args.length === 0) {
  process.stdout.write(
    'Bible Companion evaluation CLI\n\n--plan [--models=ID,ID] [--questions=10] [--repetitions=2] [--mode=grounded-generation]\n--offline: deterministic scripted plumbing checks, no network, no real quality/latency/cost measurement\n--live: deliberately unavailable until account connection, consent and budget approval are configured in the authenticated backend\n',
  );
} else if (args.includes('--live')) {
  process.stderr.write(
    'LIVE_INFERENCE_DISABLED: No credentials are read by this CLI. Connect and authorize a bounded plan through the backend; never treat fixture output as model quality.\n',
  );
  process.exitCode = 2;
} else {
  try {
    const count = Number(option('--questions') ?? (args.includes('--offline') ? '12' : '10'));
    if (!Number.isInteger(count) || count < 1 || count > 12)
      throw new Error('Questions must be 1–12.');
    const plan = createEvaluationPlan({
      modelIds: option('--models')?.split(','),
      caseIds: BIBLE_QUESTIONS.slice(0, count).map((test) => test.id),
      repetitions: Number(option('--repetitions') ?? 1),
      mode: (option('--mode') ?? 'grounded-generation') as EvaluationPlan['mode'],
    });
    if (!args.includes('--offline')) process.stdout.write(`${JSON.stringify(plan, null, 2)}\n`);
    else {
      const checks = [];
      for (const job of plan.jobs) {
        const test = BIBLE_QUESTIONS.find((test) => test.id === job.caseId)!;
        const input = { ...inputForCase(test), modelId: job.modelId };
        const authorization = offlineFixtureAuthorization('offline-fixture-owner', job.modelId);
        const prepared = prepareCompanionRequest(input, { authorization, answerMode: plan.mode });
        const selected = eligibleClaims(prepared.retrieval.sources).filter((c) =>
          test.expectedClaimIds.includes(c.claim.id),
        );
        const scripted =
          plan.mode === 'reviewed-claim-selection'
            ? { status: test.expectedStatus, claimKeys: selected.map((c) => c.key) }
            : {
                status: test.expectedStatus,
                claims: selected.map((c) => ({
                  text: c.claim.text,
                  kind: c.claim.kind,
                  sourceId: c.source.id,
                  evidenceQuote: c.claim.evidenceQuote,
                  ...(c.claim.tradition ? { tradition: c.claim.tradition } : {}),
                })),
              };
        const answer = await createCompanionAnswer(input, {
          authorization,
          answerMode: plan.mode,
          now: () => 0,
          ai: { run: async () => ({ response: JSON.stringify(scripted) }) },
        });
        checks.push({
          caseId: test.id,
          modelId: job.modelId,
          repetition: job.repetition,
          contractAccepted: true,
          status: answer.status,
          sourceIds: answer.citations.map((c) => c.sourceId),
          actualProviderUsage: null,
          modelQualityScore: null,
          providerLatencyMs: null,
        });
      }
      process.stdout.write(
        `${JSON.stringify({ kind: 'offline-scripted-contract-check', warning: 'NOT a live model evaluation. Scripted expected outputs test parsers and boundaries; Japanese quality, semantic entailment, latency, actual cost and model adoption are unmeasured.', networkRequests: 0, liveModelCalls: 0, checks }, null, 2)}\n`,
      );
    }
  } catch (error) {
    process.stderr.write(
      `${error instanceof HarnessError ? error.code : error instanceof Error ? error.message : 'Evaluation failed'}\n`,
    );
    process.exitCode = 1;
  }
}
