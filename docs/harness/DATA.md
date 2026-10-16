# Data validation and evaluation

`make data` checks the current bundled entity profiles without rewriting them, runs mutation tests that prove invalid identity references/verses/licenses/Wikipedia evidence/coordinates fail, runs existing checkpoint/context/review/primary-alignment tests and simulator-selector tests. `make swift` additionally runs every core test against the actual lookup/filtering code. No network or model is needed.

The structural gate adapts to the profile document's book/scope rather than prescribing the next release's item count. It checks unique stable IDs, canonical verse bounds/order, referential integrity, attribution/license URLs, secondary Wikipedia classification, explicit identity verification evidence, finite Earth coordinates with uncertainty disclosure, and distinct direct/context occurrences. A valid URL is not proof that a page exists or identifies the right person. Online URL verification is a separate recorded source-comparison task.

Existing `ActsEntityCoverageTests` traverses all 1,007 Acts verse positions, checks visible facts/sources against the reading end, map candidate/reviewed separation and same-name identity cases. `EntityProfilePilotTests`, `BundledEntityIndexTests`, `PlaceLocationTests`, `CitationProvenanceTests` and `StaticCommentaryTests` cover source/license safety, Wikipedia classification, context links and commentary alignment. Keep these behavior tests; do not regenerate their expected values to make a failure disappear. For a newly published book, add equivalent exhaustive verse coverage with book-specific golden identity cases before declaring it covered. The Acts gate alone does not establish Romans/Leviticus acceptance.

## Outcome-based semantic evaluation

For each changed book, retain the existing review ledger format and compare the exact candidate hash against pinned source witnesses. Record the sample set, source versions, evaluator, findings, corrections and unresolved items. Required cases:

| Dimension | Concrete acceptance example |
| --- | --- |
| Identity | Saul the king vs Saul/Paul; John the Baptist vs apostle; office titles and unknown eponyms stay qualified |
| Verse mapping | First/last chapter, empty verse with reason, direct name vs contextual identity; alternate versification must use explicit alignment |
| Sources/rights | Every claim resolves to an actual source with attribution/license; distinguish primary observation from interpretation |
| Wikipedia | Article actually identifies the entity; missing/ambiguous article stays absent; external future-content warning remains visible |
| Spoilers | At the earliest occurrence, future names/facts remain hidden until the recorded boundary or explicit reveal |
| Geography | Candidate vs independently checked point, ancient region vs modern city, ambiguous/no point, known wrong coordinates stay hidden |

Use deterministic checks first, followed by source comparison and actual UI inspection. Model opinion alone is not ground truth. Report counts of checked/passed/revised/unresolved cases; do not claim expert review or complete semantic spoiler safety. The current pinned release reports 225 profiles, 217 Wikipedia links and 4 independently checked points; these are audit facts for v0.1.10, not permanent limits on future data.

## Existing resumable generation jobs

Reuse `scripts/commentary/codex-jobs.py`; it is a local job/validation CLI with **no provider client**, and can be operated by any person or AI. A currently authorized subscription assistant reads a packet and writes the declared JSON format. No new key or model subscription is needed. Its current prompt deliberately pins `gpt-6-luna`; changing model/prompt/schema is an explicit reviewed job identity change, never a fallback.

```sh
python3 scripts/commentary/codex-jobs.py --root .cache/my-commentary prepare --book ACT --ranges 18:7-11 --max-workers 1 --max-attempts 2 --max-chars 200000 --min-spacing 1
python3 scripts/commentary/codex-jobs.py --root .cache/my-commentary status
python3 scripts/commentary/codex-jobs.py --root .cache/my-commentary claim --worker author-1
# Read the returned packet; write the exact output schema to its returned output path.
# Use returned IDs/leases below, never invent them:
python3 scripts/commentary/codex-jobs.py --root .cache/my-commentary submit --job JOB_ID --lease LEASE --file OUTPUT_JSON
python3 scripts/commentary/codex-jobs.py --root .cache/my-commentary review --job JOB_ID --file REVIEW_JSON
python3 scripts/commentary/codex-jobs.py --root .cache/my-commentary export --file .cache/reviewed-candidate.json
```

The example range is an existing complete original meaning unit. Do not split/truncate source prose merely to fill a packet. `prepare` pins source catalog/corpus hash, prompt/schema/model and passage into the job ID. SQLite WAL transactions retain per-item state, attempts, revisions and events; packets use atomic replace. Submission rejects stale/foreign leases and verifies exact quotes, ranges, source IDs and density. Review binds the exact draft hash and a different evaluator. Export requires every job source-reviewed and writes a new candidate, never bundled app data. Structural pass is not semantic review.

After interruption run `status` on the **same root**, inspect prior outputs/events, then `resume` if paused and `claim`. Expired leases become eligible under the original attempt cap; accepted items remain accepted. Re-run `prepare` only with the exact original ranges and limits; changed inputs create different IDs. `fail --job JOB_ID --lease LEASE --reason quota` or `spawn-limit` pauses dispatch without model fallback. `pause` stops new claims but does not cancel running work. Never delete the job DB as a retry strategy. For a checkpoint backup, pause and stop writers, then use SQLite's backup API; copying only the live `.sqlite` without its WAL is unsafe.

This CLI generates commentary, not the new entity datasets. Entity candidates continue to use `data/entity-profiles/` evidence and review ledgers; do not repurpose commentary packets as entity schemas. Generalize only when an actual book workflow requires it. Publication is a separate reviewed diff with retained source witnesses, successful `make data`/Swift/UI results, and deliberate release handling.
