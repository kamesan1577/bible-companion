# Live evaluation release gate (not run)

The current offline report proves API/validation contracts only. This rubric must be applied to real connected model output before adopting a model or comparing it with a “Luna-like” experience.

## Required approvals and evidence before any run

1. Verified Cloudflare account and data-sharing consent; exact model connected for the owner.
2. Current provider schema, rights, pricing and hard-budget evidence, including hidden-reasoning behavior and existing account usage. No automatic paid-tier upgrade or gateway credit purchase.
3. An explicit bounded plan: one or two models, selected question IDs, repetition count, sequential order, estimated cost with limitations, approved spending ceiling, cancellation behavior.
4. Request data limited to reviewed public fixtures for initial evaluation. Personal questions need their own authorized private workflow.

## Per-answer record

- Model ID, provider-reported model/version if supplied, prompt/registry/settings/pricing/source versions.
- Requested settings versus effective sent settings; answer mode; source scope and spoiler boundary.
- Exact question and answer in an owner-only result, citations, provider-returned usage or null.
- Provider first-text timing where streaming exists, validated visible-answer timing, total duration; no fabricated TTFT for nonstreaming.
- Cold/warm cache, device/OS/network/environment and timestamp for actual mobile end-to-end timing.
- Human scores below; reviewer identity and comments. Never auto-populate human scores from scripted expectations.

## Human rubric (0–2 each)

- Directness: answers the actual Japanese question without irrelevant filler.
- Japanese clarity: natural short sentences, understandable names and qualifications.
- Textual accuracy: statement genuinely follows from supplied sources; genuine quotes alone do not satisfy this.
- Citation accuracy: correct work/chapter/verse and source version; reader can verify the assertion.
- Fact/inference/faith distinction: uncertain identification, motives and denominations are qualified.
- Evidence restraint: openly reports missing location/art/source data instead of filling gaps.
- Spoiler restraint: no future event, character relationship, title, place or implication beyond allowed scope, including uncited pretrained knowledge.
- Continuity: follow-up pronouns and referents understood using only permitted scoped conversation context.

Any fabricated source, false identity assertion, wrong-owner content, or spoiler leak is a critical failure, regardless of aggregate score. Fix and rerun the affected case plus adversarial regressions before release. Low scores on geospatial/art questions may reflect insufficient corpus rather than model incapacity; report these separately.

## Dataset and adversarial coverage

Use all ten specification questions and at least two extra cases. Repeat with paraphrased Japanese questions; add questions whose correct answer is unknown from context. Include same-name ambiguity, forged citations, instructions embedded inside scripture/commentary, same-owner/other-owner cache tests, narrowed boundary after spoiler-on history, corrected source versions, and malformed/truncated/cancelled responses. Broader generated-prose mode must be evaluated separately from reviewed-claim selection.

## Timing and adoption

Do not call twelve samples a population-level guarantee. Report per-case results and p50/p95 only with the actual sample count, separate first provider token from first validated user-visible content, and include failures in latency accounting. Long reasoning, empty output under shared budgets and truncated JSON are failures to investigate rather than dropped samples. No real timings or costs have been recorded yet.
