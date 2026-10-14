# Public-domain primary-text corpus

## Scope and rights

This preparation path selects the 66-book Protestant canon from the publisher's World English Bible USFX source. It adds English primary text only. It does not copy the Japanese Contemporary Bible (JCB), translate the WEB into Japanese, create commentary, mark commentary reviewed, or establish textual equivalence between different translations.

Verified official sources on 2026-10-13:

- [Publisher edition and public-domain declaration](https://ebible.org/details.php?id=engwebp)
- [Official USFX archive](https://ebible.org/Scriptures/engwebp_usfx.zip)
- [Publisher's Protestant edition](https://ebible.org/engwebp/)
- [Publisher's USFX format description](https://ebible.org/usfx/)

The publisher dedicates the translation to the public domain. “World English Bible” is a trademark; substantially edited text must not be presented as an unchanged WEB edition. The preparation preserves primary words and punctuation, with only the documented extraction and layout-whitespace normalization below. Keep that extraction policy visible to operators. This is an observation of the publisher's rights statement, not a claim that the app has obtained rights to unrelated translations or annotations.

The source is downloaded from a fixed public HTTPS URL with no login, accepted agreements, private APIs, AI calls, or paid services. Only one named XML member is read; bundled CSS, keys and other files are never installed or executed.

## Offline repository bundle

`data/scripture/webp-2026-10-13/` preserves gzip-compressed primary-text outputs plus the pinned manifest and rights/provenance README (approximately 1.69 MB total). Gzip uses `mtime=0` and no filename. This is operator data, never a Worker import or public static asset.

```sh
node scripts/scripture-corpus.mjs verify-bundled
node scripts/scripture-corpus.mjs restore-bundled
```

Both commands are offline and require Node/project dependencies only. `restore-bundled` verifies the code-pinned manifest and decompressed output hashes before restoring the same default prepared artifacts; it also accepts `--out-dir` within `.cache/scripture/`. This makes local import reproducible when the mutable publisher archive changes. Bundled integrity verification does not repeat original-XML extraction; the separate `prepare`/`verify` flow below does.

## Reproduce locally

Prerequisites: Node 24+, project dependencies (`npm ci`), and Python 3's standard library for bounded ZIP reading.

```sh
node scripts/scripture-corpus.mjs fetch
node scripts/scripture-corpus.mjs prepare
node scripts/scripture-corpus.mjs verify
```

`fetch` is the only network step. It accepts no alternative destination or URL. `prepare` and `verify` are offline and accept `--archive PATH` and `--out-dir PATH`; output must remain inside this checkout's `.cache/scripture/` and may not traverse symlinks. These commands do not write to D1 or deploy anything. Import and runtime rights activation are a separate, guarded workflow.

Default artifacts, all ignored by Git:

- `.cache/scripture/engwebp_usfx.zip`: unmodified publisher archive
- `.cache/scripture/latest-download-receipt.json`: actual time of a subsequent CLI download
- `.cache/scripture/prepared/verses.ndjson`: all selected source verse markers, including explicit empty/unsupported records
- `.cache/scripture/prepared/unversified.ndjson`: source `d` sections, separate from numbered verses
- `.cache/scripture/prepared/manifest.json`: provenance, policy, counts and all coordinate differences
- `.cache/scripture/prepared/manifest.sha256`: exact manifest byte digest

`verify` reproduces all four prepared artifacts from the pinned archive in memory and compares their bytes. A change to the publisher archive, extracted XML, parser output or manifest fails closed. A newer upstream download requires explicit source/rights review, new immutable version and hash pins; do not bypass the digest check to make an import pass. Keep an operator-controlled copy of the original pinned archive if long-term reproducibility is needed: the official download URL is mutable and may stop serving this exact snapshot.

## Immutable snapshot

Identity:

- corpusId / sourceId: `webp`
- edition: `engwebp`
- language: `en`
- referenceSystem: `web-protestant`
- version: `webp-usfx-2026-10-13-35a6adf626e5`
- parserVersion: `webp-usfx/1`
- archive member: `engwebp_usfx.xml`
- original snapshot acquisition (`fetchedAt`): `2026-10-13T18:55:08.167Z`

SHA-256 digests:

```text
archive     35a6adf626e563573fdbfb7c89ac8b1d7c5a11df30b54d2566aca7b1f23ec6dc
XML         61e697d234b92af31edca8804d2041a7f5e68136779573fb3bcfeff7e9cbce58
verses      ac01776530f30e7f8cdac3d40987a70b4eb7966388431e0951d511c2ddba2455
unversified b2a4dfaaa959ae76be4157c01fce4c2a5a504037dadf87abf2aaef1c5311d8e6
manifest    d2f923bc56cb6e2e77f0f5a3e9cbd6a29f7a3028a3db011e0be8cad4f591449e
```

The manifest's acquisition time describes this original, byte-pinned snapshot, not each later preparation. No current preparation time is injected. Subsequent downloads have a separate receipt so reproducing the same version remains deterministic. Manifest bytes are UTF-8 `JSON.stringify(manifest, null, 2) + '\n'`; NDJSON is each record in the parser's fixed property order, with one final LF. Digests cover exact bytes, not reserialized JSON.

The pure parser and preparer are not a trust-authority boundary. A caller can supply fixture bytes and expected fixture hashes to their exported functions. Runtime grounding must independently require the code-pinned corpus identity and exact manifest digest, immutable imported rows, and active rights status. Self-asserted `verification` strings or hashes are insufficient.

## Measured source differences

This exact archive contains 83 book blocks, although the publisher's Protestant edition page describes 66. Selection therefore uses the explicit canonical book-ID allowlist, never the archive name alone.

Selected output:

- 66 books, 1,189 chapter markers
- 31,103 source verse markers
- 31,098 nonempty source verses
- 31,100 coordinate-compatible verse markers, of which 31,095 have primary text
- 3 unsupported nonempty source verses
- 138 separate `d` sections: Psalm superscriptions and Psalm 119 acrostic labels

Excluded source blocks and their verse-marker counts:

```text
FRT 0; TOB 244; JDT 339; ESG 205; WIS 436; SIR 1383; BAR 213;
1MA 924; 2MA 555; 1ES 448; MAN 15; PS2 7; 3MA 228; 2ES 944;
4MA 484; DAG 530; GLO 0.
```

Exact coordinate/text gaps against the app's existing standardKJV `verse-counts.json`:

- Source ROM 14:24, 14:25 and 14:26 are preserved with `canonical: null`, `alignment: "unsupported"`.
- Canonical ROM 16:26 and 16:27 have no source marker and remain absent.
- Source LUK 17:36, ACT 8:37, ACT 15:34, ACT 24:7 and ROM 16:25 contain notes but no primary words. Their records retain `text: ""` and `textStatus: "empty"`. Notes are not substituted for scripture.
- This snapshot's 3 John ends at source 1:14. A hypothetical or later 1:15 is unsupported by current canonical metadata and is never silently folded into 1:14.

Coordinate compatibility means only that an integer coordinate exists in the app's canonical metadata. It does not prove word-for-word equivalence, matching verse boundaries, textual-critical agreement, or Japanese-translation alignment. Romans' doxology is not moved from chapter 14 to chapter 16. Bridged (`16-17`) and suffixed (`18a`) labels are preserved verbatim and left unsupported; they are not split into synthetic rows.

## Extraction policy

1. Require all 66 allowed book blocks and every expected chapter marker in production mode. A partial mode exists only for offline fixtures or explicit inspection.
2. Use USFX chapter/verse milestones, not rendered headings or display numbers. Source `bcv`, when supplied, must agree with the book/chapter/verse marker.
3. Preserve primary inline text, including word spans, words-of-Jesus spans, original punctuation and `Selah`. Remove only formatting markup. Never insert spaces inside word spans (`LORD` + `’s`, for example).
4. Exclude footnotes, crossreferences, introductions, book/section headings, alternate display numbers and speaker labels. The manifest records the number of excluded outer elements by kind. Note text is never eligible primary text.
5. Collapse only ASCII space, tab, carriage return and line feed runs into one space, and trim those characters at record boundaries. Paragraph/poetry/blank-line boundaries contribute a space. Nonbreaking spaces, apostrophes, quotation marks and Unicode normalization remain unchanged.
6. Preserve `d`-marked source superscriptions and acrostic labels separately. `afterSourceVerse: null` anchors a section at chapter start; a source verse label anchors it after that verse. In Psalm 119 the publisher places some preceding `ve` markers inside the next `d` block. The parser honors those milestones while keeping acrostic labels out of the preceding verse's words. No verse 0 is invented.
7. Retain empty and unsupported numbered source records in the local artifacts so operators can audit all omissions. The application must exclude them from ordinary canonical primary-text grounding and give explicit unavailable/unsupported results for affected requests.

Every record is `verification: "literal-source"`, `editorialReview: "unreviewed"`. The manifest says the exact XML digest was verified and explicitly says `humanTextReview: false`. These flags never mark generated explanations, Japanese commentary, historical claims or theology as reviewed.

## Storage and integration contract

The exact exported types are in `packages/core/src/scripture-corpus.ts`.

A numbered NDJSON record has:

```json
{
  "sourceId": "webp",
  "version": "webp-usfx-2026-10-13-35a6adf626e5",
  "sourceBook": "GEN",
  "sourceChapter": 1,
  "sourceVerse": "1",
  "text": "In the beginning, God created the heavens and the earth.",
  "canonical": { "book": "GEN", "chapter": 1, "verse": 1 },
  "alignment": "canonical-compatible",
  "textStatus": "present",
  "verification": "literal-source",
  "editorialReview": "unreviewed"
}
```

Its unique primary coordinate is `(sourceId, version, sourceBook, sourceChapter, sourceVerse)`, with `sourceVerse` deliberately a string. Only nonempty records with a non-null canonical coordinate can be candidates for ordinary numeric canonical retrieval; immutable identity/digest/rights checks are additional requirements.

An unversified record has sourceId, version, sourceBook, sourceChapter, marker `d`, afterSourceVerse, text, verification and editorialReview. Multiple records may share a chapter. Their source-order index is meaningful; do not infer a numbered verse from their position.

The manifest contains sourceURL, licenseURL, license, edition, language, referenceSystem, version, fetchedAt, archive/XML/output hashes, parserVersion, all book and total counts, all excluded books, unsupportedVerses, emptyVerses, missingCanonicalVerses, excludedElementCounts, parsingPolicy and verification status. No private reading data is present.

Public citation links were verified against all 66 entries in the publisher's official table of contents on 2026-10-13. Book codes match the canonical codes. Chapter filenames use three digits for Psalms and two for other books:

```js
`https://ebible.org/engwebp/${book}${String(chapter).padStart(book === 'PSA' ? 3 : 2, '0')}.htm`;
```

Examples: [Psalm 1](https://ebible.org/engwebp/PSA001.htm), [1 Samuel 1](https://ebible.org/engwebp/1SA01.htm), [1 Corinthians 1](https://ebible.org/engwebp/1CO01.htm). The live website can change; the pinned corpus remains the provenance for imported text.

## Defensive limits and verification

The strict `saxes` reader rejects malformed XML, unknown entities, DTDs/external entities, processing instructions, CDATA, unknown selected-book markup/styles, conflicting coordinate markers, missing end markers, duplicates, unassigned primary text, input above 64 MiB, nesting beyond 64, verse/section text above 100,000 characters, and more than 50,000 total verse markers. It does not fetch schema URLs. ZIP download is limited to 20 MiB, extraction to 64 MiB, 30 seconds and one exact non-encrypted regular member; extraction validates ZIP CRC and then the pinned XML SHA-256.

Offline tests cover extraction fidelity, note-only verses, all-66 coverage, excluded books, Psalm 119 milestone placement, coordinate differences, exact hashes, UTF-8 errors and adversarial markup. They do not download the corpus, call a model, access private APIs or require fulltext to be committed.

```sh
npx vitest run packages/core/test/scripture-corpus.test.ts
npm run typecheck
node scripts/scripture-corpus.mjs verify
```

This verifies a reproducible literal-source artifact. Editorial review and permission to deploy remain separate.

### Observed snapshot validation (2026-10-13)

The actual official archive was downloaded and hash-checked. All generated bytes reproduced after formatting and verification. An independent Python ElementTree extractor matched every one of the 31,103 numbered verse texts and 138 unversified sections against the saxes-generated records, including punctuation, whitespace and empty markers. This was an extraction-fidelity check against the same source, not independent translation/editorial review. The CLI's fixed official-URL download also succeeded and recorded its separate retrieval receipt.

## Guarded local D1 import

```sh
npm run corpus -- restore-bundled
npm run migrate
npm run corpus:import
npm run corpus:import -- --execute
```

The default import command reports a plan without writing. Explicit execution verifies the pinned manifest and both artifact hashes, checks every source row and canonical coordinate, stages immutable rows, rereads every stored field, and seals the complete revision with an atomic pending-to-approved activation guard. Partial staging can resume; an already-ready identical corpus is a zero-write replay. Conflicting text, another active revision, changed hashes, revoked policy, remote flags and arbitrary config overrides fail closed. The138 unversified sections are integrity checked but not inserted as numbered verses.

Actual local verification on2026-10-13 imported31,103 source rows, of which31,095 are readable coordinate-compatible text, and immediately replayed with zero writes. This is not a deployed service or a statement that every canonical reference is present. The authenticated `/v1/imports/{id}/scripture` endpoint returns at most100 verses/120KB item bytes per page and explicit in-range omissions. Long ranges are paged rather than requiring the complete range in phone memory; individual verses are never silently truncated.

Remote import is deliberately unsupported. Indexed corpus writes can exceed D1 Free's daily write allowance; see the [storage ADR](adr/0001-public-scripture-storage.md) and [operations gate](OPERATIONS.md). An optional static-assets adapter is being evaluated without changing the public reading contract.
