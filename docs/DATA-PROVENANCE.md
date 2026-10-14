# Data provenance

`packages/core/src/verse-counts.json` contains chapter verse counts only (no Bible text), from the public-domain Bible Metadata collection: https://github.com/jpoehls/bible-metadata, retrieved 2026-10-13 from https://raw.githubusercontent.com/jpoehls/bible-metadata/master/Chapters.csv. Source SHA-256: 46ea66bf97e1613342407d4e6c827f322083a25866d45a5f9a7c7a29474a53e3

Validated totals: 66 books, 1,189 chapters, 31,102 verse positions. This is standard Protestant/KJV versification, not a guarantee that every translation includes every verse or uses identical numbering. Translation-specific mapping must be reviewed before enabling alternate versifications. Japanese and English aliases are local application metadata. No JCB Bible text is bundled or persisted by the API.

## Reviewed source seed

`packages/ai-harness/fixtures/acts-sources.ts` and migration `0003_reviewed_sources.sql` contain nine short English World English Bible excerpts plus original Japanese explanatory notes. Source text and public-domain status were verified on 2026-10-13:

- https://ebible.org/engwebp/ACT16.htm
- https://ebible.org/engwebp/ACT17.htm
- https://ebible.org/engwebp/ACT18.htm
- https://ebible.org/engwebp/copyright.htm

Each source preserves a direct verse link, version, license, review flag, passage range, spoiler end, claim category and exact evidence quotation. Japanese notes are original commentary, not a JCB translation. The future Acts18:24–26 item exists to test exclusion at earlier boundaries. These nine sources are a limited starter corpus, not a comprehensive Bible commentary. No pictures or maps are bundled without separate rights review.

To regenerate the deterministic seed after a reviewed fixture update: `node --experimental-strip-types scripts/generate-source-seed.mjs`. Once any migration is deployed, do not edit it: create a new migration for changes or revocations. The current source-only reader derives cache version from the live approved records, so rights revocation or correction invalidates shared cache selection immediately. Clients must also consult the content manifest to invalidate downloaded copies.
