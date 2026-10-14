#!/usr/bin/env node
/** Optional public-document check; never touches an AI inference endpoint or credential. */
import { listModels } from '../src/index.ts';
const remote = process.argv.includes('--remote');
if (process.argv.slice(2).some((arg: string) => arg !== '--remote'))
  throw new Error('Only --remote is supported.');
const results = [];
for (const model of listModels()) {
  const result: {
    id: string;
    connectionStatus: 'unconnected';
    checked: string;
    problems: string[];
    officialUrl: string;
    termsReview: (typeof model)['termsReview'];
  } = {
    id: model.id,
    connectionStatus: 'unconnected',
    checked: remote ? 'public-document-only' : 'local-metadata-only',
    problems: [],
    officialUrl: model.officialUrl,
    termsReview: model.termsReview,
  };
  if (remote) {
    try {
      const response = await fetch(`${model.officialUrl}index.md`, {
        signal: AbortSignal.timeout(15000),
        redirect: 'error',
      });
      if (!response.ok) throw new Error(`HTTP_${response.status}`);
      const text = (await response.text()).replace(/\\_/g, '_');
      if (text.length > 2_000_000) throw new Error('DOCUMENT_TOO_LARGE');
      const termsUrl = text.match(/\| Terms and License \| \[link[^\]]*\]\(([^)]+)\)/)?.[1] ?? null;
      if (termsUrl !== model.termsReview.modelTermsUrl)
        result.problems.push('MODEL_TERMS_LINK_CHANGED');
      if (!text.includes(model.id)) result.problems.push('MODEL_ID_NOT_FOUND');
      if (!text.includes(model.tokenParameter)) result.problems.push('TOKEN_PARAMETER_NOT_FOUND');
      if (text.includes('Paid access required') && model.billingTier !== 'paid-required')
        result.problems.push('BILLING_CLASS_CHANGED');
      const context = text.match(/\| Context Window[^\n]*?\| ([\d,]+) tokens/);
      if (!context || Number(context[1].replace(/,/g, '')) !== model.contextWindowTokens)
        result.problems.push('CONTEXT_LIMIT_CHANGED');
    } catch (error) {
      result.problems.push(error instanceof Error ? error.name : 'DOCUMENT_CHECK_FAILED');
    }
  }
  results.push(result);
}
process.stdout.write(
  `${JSON.stringify({ kind: 'metadata-check-not-a-connection-test', runtimeInferenceTested: false, models: results }, null, 2)}\n`,
);
if (results.some((r) => r.problems.length)) process.exitCode = 1;
