import { describe, expect, it } from 'vitest';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import counts from '../src/verse-counts.json' with { type: 'json' };
import {
  parseWebpUsfx,
  prepareScriptureCorpus,
  scriptureSha256,
  serializeScriptureVerses,
  WEBP_PINNED_SNAPSHOT,
  WEBP_SOURCE,
} from '../src/scripture-corpus.ts';

const wrap = (body: string, book = 'GEN') =>
  `<?xml version="1.0" encoding="utf-8"?><usfx><book id="${book}">${body}</book></usfx>`;
const parse = (body: string, book = 'GEN') =>
  parseWebpUsfx(wrap(body, book), { requireAll66Books: false });
const verse = (text: string, label = '1') => `<v id="${label}"/>${text}<ve/>`;
const one = (text: string) => `<c id="1"/><p>${verse(text)}</p>`;

describe('rights-safe USFX primary-text preparation', () => {
  it('pins official public-domain provenance without representing human/editorial review', () => {
    expect(WEBP_SOURCE.sourceURL).toBe('https://ebible.org/Scriptures/engwebp_usfx.zip');
    expect(WEBP_SOURCE.licenseURL).toBe('https://ebible.org/details.php?id=engwebp');
    expect(WEBP_SOURCE.license).toBe('public-domain');
    const row = parse(one('In the beginning.')).verses[0];
    expect(row).toMatchObject({
      sourceId: 'webp',
      version: WEBP_PINNED_SNAPSHOT.version,
      sourceBook: 'GEN',
      sourceChapter: 1,
      sourceVerse: '1',
      text: 'In the beginning.',
      canonical: { book: 'GEN', chapter: 1, verse: 1 },
      verification: 'literal-source',
      editorialReview: 'unreviewed',
    });
    expect(row).not.toHaveProperty('reviewed');
  });

  it('removes notes, crossreferences and editorial headings without losing inline words or punctuation', () => {
    const result = parse(
      `<id id="GEN">Publisher label</id><h>Book heading</h><toc>Book title</toc><p sfm="mt" style="mt1">Editorial title</p><c id="1"/><p>${verse('The <w s="H1">LORD</w>’s<f><fr>1:1</fr><ft>commentary &amp; <wh>Hebrew</wh></ft></f> word, <wj>“<w>let</w>’s go.”</wj><x><xo>1:1</xo><xt>Elsewhere</xt></x><ref tgt="GEN.2.1">Other verse</ref>')}</p>`,
    );
    expect(result.verses[0].text).toBe('The LORD’s word, “let’s go.”');
    expect(result.excludedElementCounts).toMatchObject({
      f: 1,
      x: 1,
      ref: 1,
      h: 1,
      toc: 1,
      'p:mt1': 1,
    });
  });

  it('normalizes ASCII layout whitespace only, with boundaries but no spaces inside styled words', () => {
    const result = parse(
      `<c id="1"/><q><v id="1"/>  Don<w>’t</w>\tchange\r\nwords.</q><q>Next\u00a0line.<qs> Selah.</qs><ve/></q>`,
    );
    expect(result.verses[0].text).toBe('Don’t change words. Next\u00a0line. Selah.');
    expect(parse(one('A&#x20;B &amp; C &lt; D &quot;E&quot; &apos;F&apos;')).verses[0].text).toBe(
      'A B & C < D "E" \'F\'',
    );
  });

  it('excludes speaker labels inside an active verse without ending its primary text', () => {
    const result = parse(
      '<c id="1"/><q><v id="1"/>One.</q><p sfm="sp" style="sp">Friends</p><q>Two.<ve/></q>',
      'SNG',
    );
    expect(result.verses[0].text).toBe('One. Two.');
  });

  it('keeps superscriptions and Psalm119 acrostic labels outside the adjacent verse', () => {
    const result = parse(
      '<c id="119"/><d>ALEPH</d><q><v id="8"/>Your statutes.</q><d>BETH<ve/></d><q><v id="9"/>A young man.<ve/></q>',
      'PSA',
    );
    expect(result.verses.map((v) => v.text)).toEqual(['Your statutes.', 'A young man.']);
    expect(result.unversified).toMatchObject([
      { sourceBook: 'PSA', sourceChapter: 119, marker: 'd', afterSourceVerse: null, text: 'ALEPH' },
      { sourceBook: 'PSA', sourceChapter: 119, marker: 'd', afterSourceVerse: '8', text: 'BETH' },
    ]);
    const psalm = parse(
      '<c id="3"/><d>A Psalm.<f><ft>footnote</ft></f></d><q><v id="1"/>LORD!<ve/></q>',
      'PSA',
    );
    expect(psalm.unversified[0].text).toBe('A Psalm.');
    expect(psalm.verses[0].text).toBe('LORD!');
  });

  it('preserves unsupported labels without splitting, merging, remapping or filling them', () => {
    const result = parse(
      '<c id="14"/><p><v id="24" bcv="ROM.14.24"/>Doxology.<ve/></p><c id="16"/><p><v id="25"/><f><ft>Elsewhere.</ft></f><ve/></p>',
      'ROM',
    );
    expect(result.verses[0]).toMatchObject({
      sourceVerse: '24',
      sourceChapter: 14,
      canonical: null,
      alignment: 'unsupported',
      text: 'Doxology.',
    });
    expect(result.verses[1]).toMatchObject({
      sourceVerse: '25',
      text: '',
      textStatus: 'empty',
      alignment: 'canonical-compatible',
    });
    expect(result.emptyVerses).toEqual([
      { sourceBook: 'ROM', sourceChapter: 16, sourceVerse: '25' },
    ]);
    expect(result.missingCanonicalVerses).toContainEqual({ book: 'ROM', chapter: 16, verse: 26 });
    const extended = parse(
      '<c id="1"/><p><v id="15"/>Fifteen.<ve/><v id="16-17" bcv="3JN.1.16"/>Combined.<ve/><v id="18a"/>Split label.<ve/></p>',
      '3JN',
    );
    expect(extended.verses.map((v) => [v.sourceVerse, v.canonical])).toEqual([
      ['15', null],
      ['16-17', null],
      ['18a', null],
    ]);
  });

  it('selects only canonical66 books and reports excluded books instead of trusting archive naming', () => {
    const xml = `<usfx><book id="FRT"><p>Preface</p></book><book id="TOB"><c id="1"/><p>${verse('Excluded book.')}</p></book><book id="GEN">${one('Primary.')}</book><book id="GLO"><p>Glossary</p></book></usfx>`;
    const result = parseWebpUsfx(xml, { requireAll66Books: false });
    expect(result.verses.map((v) => v.sourceBook)).toEqual(['GEN']);
    expect(result.excludedBooks).toEqual([
      { book: 'FRT', verseMarkerCount: 0 },
      { book: 'TOB', verseMarkerCount: 1 },
      { book: 'GLO', verseMarkerCount: 0 },
    ]);
  });

  it('requires all66 books and their known chapter markers by default', () => {
    expect(() => parseWebpUsfx(wrap(one('Sample.')))).toThrow('Missing canonical books');
    const books = Object.entries(counts)
      .map(
        ([book, chapters]) =>
          `<book id="${book}">${chapters.map((_, c) => `<c id="${c + 1}"/><p>${verse('Offline fixture.')}</p>`).join('')}</book>`,
      )
      .join('');
    const result = parseWebpUsfx(`<usfx>${books}</usfx>`);
    expect(result.books).toHaveLength(66);
    expect(result.verses).toHaveLength(1189);
    expect(result.books[65]).toMatchObject({ book: 'REV', chapterCount: 22, verseCount: 22 });
    expect(() => parseWebpUsfx(`<usfx>${books.replace('<c id="50"/>', '')}</usfx>`)).toThrow();
  });

  it('serializes deterministically and binds exact XML and output bytes in the manifest', async () => {
    const bytes = new TextEncoder().encode(wrap(one('Primary &amp; exact.')));
    const provenance = { ...WEBP_PINNED_SNAPSHOT, xmlSha256: await scriptureSha256(bytes) };
    const first = await prepareScriptureCorpus(bytes, provenance, { requireAll66Books: false });
    const second = await prepareScriptureCorpus(bytes, provenance, { requireAll66Books: false });
    expect(first).toEqual(second);
    expect(first.manifest).toMatchObject({
      corpusId: 'webp',
      sourceId: 'webp',
      edition: 'engwebp',
      referenceSystem: 'web-protestant',
      language: 'en',
      fetchedAt: '2026-10-13T18:55:08.167Z',
      verification: {
        sourceText: 'xml-sha256-verified',
        editorialReview: 'unreviewed',
        humanTextReview: false,
      },
    });
    expect(first.manifest.hash.verses).toBe(
      await scriptureSha256(new TextEncoder().encode(first.versesNdjson)),
    );
    expect(serializeScriptureVerses(first.verses)).toBe(first.versesNdjson);
    expect(first.versesNdjson.endsWith('\n')).toBe(true);
    await expect(
      prepareScriptureCorpus(
        bytes,
        { ...provenance, xmlSha256: '0'.repeat(64) },
        { requireAll66Books: false },
      ),
    ).rejects.toThrow('SHA-256');
    await expect(
      prepareScriptureCorpus(
        bytes,
        { ...provenance, fetchedAt: 'yesterday' },
        { requireAll66Books: false },
      ),
    ).rejects.toThrow('timestamp');
  });
});

describe('fail-closed parser boundaries', () => {
  it.each([
    ['DTD', '<!DOCTYPE usfx [<!ENTITY attack "bad">]><usfx/>'],
    ['external entity', '<!DOCTYPE usfx SYSTEM "https://evil.test/entity"><usfx/>'],
    ['processing instruction', '<usfx><?xml-stylesheet href="https://evil.test/x"?></usfx>'],
    ['unknown entity', wrap(one('&unknown;'))],
    ['malformed entity', wrap(one('A & B'))],
    ['illegal XML character', wrap(one('\u0000'))],
    ['duplicate attribute', '<usfx><book id="GEN" id="EXO"/></usfx>'],
    ['unclosed XML', '<usfx><book id="GEN">'],
    ['root text', '<usfx>Unassigned text<book id="GEN"/></usfx>'],
    ['CDATA', wrap(one('<![CDATA[surprise]]>'))],
    ['unexpected namespace', '<ns:usfx xmlns:ns="https://example.com"/>'],
    ['unknown primary tag', wrap(one('<mystery>Words</mystery>'))],
    ['unknown paragraph style', wrap('<c id="1"/><p style="magic">Words</p>')],
    ['mismatched style', wrap('<c id="1"/><p sfm="mt" style="p">Words</p>')],
    ['annotation outside note', wrap(one('<ft>Words</ft>'))],
    ['text before chapter', wrap('<p>Unassigned words.</p>')],
    ['text outside verse', wrap('<c id="1"/><p>Unassigned words.</p>')],
    ['missing verse end', wrap('<c id="1"/><p><v id="1"/>Words</p>')],
    ['double verse end', wrap(one('Words').replace('<ve/>', '<ve/><ve/>'))],
    ['overlapping verse', wrap('<c id="1"/><p><v id="1"/>Words<v id="2"/>More<ve/></p>')],
    ['duplicate verse', wrap(`<c id="1"/><p>${verse('Words')}${verse('More')}</p>`)],
    ['duplicate book', '<usfx><book id="GEN"/><book id="GEN"/></usfx>'],
    ['duplicate chapter', wrap('<c id="1"/><c id="1"/>')],
    ['chapter within verse', wrap(one('<c id="2"/>'))],
    ['marker inside note', wrap(one('<f><v id="2"/>Intrusion</f>'))],
    ['marker with body', wrap('<c id="1"/><p><v id="1">Words</v><ve/></p>')],
    ['conflicting bcv', wrap('<c id="1"/><p><v id="1" bcv="EXO.1.1"/>Words<ve/></p>')],
    ['padded chapter', wrap('<c id="01"/><p/>')],
    ['verse0', wrap('<c id="1"/><p><v id="0"/>Words<ve/></p>')],
    ['negative verse', wrap('<c id="1"/><p><v id="-1"/>Words<ve/></p>')],
  ])('rejects %s', (_label, xml) => {
    expect(() => parseWebpUsfx(xml, { requireAll66Books: false })).toThrow();
  });

  it('bounds nested markup and per-verse text', () => {
    expect(() => parse(one('<w>'.repeat(70) + 'Word' + '</w>'.repeat(70)))).toThrow('nesting');
    expect(() => parse(one('x'.repeat(100_001)))).toThrow('too long');
  });
  it('bounds total markers even in excluded books', () => {
    const xml = '<usfx><book id="TOB">' + '<v id="1"/>'.repeat(50_001) + '</book></usfx>';
    expect(() => parseWebpUsfx(xml, { requireAll66Books: false })).toThrow(
      'Too many verse markers',
    );
  });
  it('bounds bytes before parsing or hashing', async () => {
    await expect(
      prepareScriptureCorpus(new Uint8Array(64 * 1024 * 1024 + 1), WEBP_PINNED_SNAPSHOT),
    ).rejects.toThrow('64 MiB');
  });
  it('rejects invalid UTF-8 even when the supplied byte digest matches', async () => {
    const bytes = new Uint8Array([0xc0, 0xaf]);
    await expect(
      prepareScriptureCorpus(bytes, {
        ...WEBP_PINNED_SNAPSHOT,
        xmlSha256: await scriptureSha256(bytes),
      }),
    ).rejects.toThrow();
  });
  it('rejects output outside cache before reading an archive', () => {
    const script = new URL('../../../scripts/scripture-corpus.mjs', import.meta.url);
    const result = spawnSync(
      process.execPath,
      [script.pathname, 'prepare', '--out-dir', tmpdir()],
      { encoding: 'utf8' },
    );
    expect(result.status).toBe(1);
    expect(result.stderr).toContain('Output must remain inside');
  });
  it('rejects an unpinned archive without creating prepared artifacts', () => {
    const directory = mkdtempSync(join(tmpdir(), 'scripture-corpus-'));
    const archive = join(directory, 'untrusted.zip');
    const output = resolve('.cache/scripture', directory.split('/').at(-1)!);
    try {
      writeFileSync(archive, 'not the official archive');
      const script = new URL('../../../scripts/scripture-corpus.mjs', import.meta.url);
      const result = spawnSync(
        process.execPath,
        [script.pathname, 'prepare', '--archive', archive, '--out-dir', output],
        { encoding: 'utf8' },
      );
      expect(result.status).toBe(1);
      expect(result.stderr).toContain('Archive SHA-256 mismatch');
      expect(existsSync(output)).toBe(false);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
  it('verifies the bundled pinned outputs offline without claiming a fresh XML parse', () => {
    const script = new URL('../../../scripts/scripture-corpus.mjs', import.meta.url);
    const result = spawnSync(process.execPath, [script.pathname, 'verify-bundled'], {
      encoding: 'utf8',
    });
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toMatchObject({
      originalXmlReparsed: false,
      verification: 'bundled-output-integrity',
      manifestSha256: WEBP_PINNED_SNAPSHOT.manifestSha256,
      books: 66,
      verses: 31103,
    });
  });
  it('exposes safe CLI help and rejects unsupported remote/import flags without network or database access', () => {
    const script = new URL('../../../scripts/scripture-corpus.mjs', import.meta.url);
    const help = spawnSync(process.execPath, [script.pathname, '--help'], { encoding: 'utf8' });
    expect(help.status).toBe(0);
    expect(help.stdout).toContain('No D1 writes');
    const invalid = spawnSync(process.execPath, [script.pathname, 'prepare', '--remote'], {
      encoding: 'utf8',
    });
    expect(invalid.status).toBe(1);
    expect(invalid.stderr).toContain('Unknown, duplicate or incomplete option');
  });
});
