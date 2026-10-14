# Grounded output reference audit

Reviewed 2026-10-13 against the local source. No provider, credentials, deployment or external calls were used.

## Finding and correction

The experimental generated-output checker recognized canonical short codes and Acts aliases, but not Japanese names for other books. Under an Acts 18:18 boundary, `ヨハネ3:16` was therefore read as an unqualified Acts 3:16 reference and accepted. Long English names could also be misread as a short suffix rather than the intended book. This affected generated prose and faith labels, not the default reviewed-claim selection renderer.

The checker now shares the import parser's immutable, longest-first alias list. It recognizes all 66 canonical Japanese and English book names, existing short names and numbered-book variants, normalized fullwidth characters, abbreviation dots, and opening citation brackets. Unqualified chapter/verse references retain the current book. Ordinary English words such as “See” or “In” are no longer mistaken for arbitrary book codes.

Regression coverage lives in `packages/ai-harness/test/reference-aliases.test.ts`. Four focused tests cover all canonical names, alias/punctuation variants, valid unqualified references, future/invalid verses, and both generated prose and faith labels. The change does not claim detection of every natural-language reference, paraphrase, or implicit event spoiler.

## Trust boundary review

- Imported raw share text does not become a reviewed source. The API constructs evidence from server-owned source snapshots and pinned primary-text provenance.
- Question, history and source text remain untrusted JSON data under the system prompt. No source text or URL authorizes tools, arbitrary providers or additional evidence.
- Default selection accepts only keys from the retrieved reviewed claim set. It never renders new model-authored prose.
- Experimental generation validates allowed source IDs, exact evidence quotes and known explicit references. These checks do not prove entailment, Japanese quality or semantic spoiler safety; the existing warnings and separate consent remain necessary.
- Private/source-version/history scopes and source rights are checked before prompt construction; saved visibility uses authoritative source identities rather than generation relevance ranking.
- Unconnected inference fails explicitly. Source-only output remains labeled non-AI. No live readiness, pricing measurement or model-quality claim follows from these local tests.

## Reproduction commands

- `npx vitest run packages/ai-harness/test/reference-aliases.test.ts`
- `npx vitest run packages/ai-harness/test packages/core/test`
- `npm run typecheck`
- `npm test`

Live model/human evaluation, deployed provider/account gates, actual Apple SDK/device acceptance, stable authentication origin, and private GitHub publication remain release blockers as documented in `docs/acceptance-status.md`.
