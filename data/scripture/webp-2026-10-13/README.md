# Pinned public-domain scripture data

This operator-only bundle preserves the exact derived English primary-text outputs of `webp-usfx-2026-10-13-35a6adf626e5` when the publisher's mutable download changes. It is separate repository data, never a Worker module, runtime import, application seed migration or browser asset.

Source: [official eBible engwebp USFX archive](https://ebible.org/Scriptures/engwebp_usfx.zip). Rights: [publisher's public-domain declaration](https://ebible.org/details.php?id=engwebp). Original snapshot acquired 2026-10-13T18:55:08.167Z. The World English Bible text is dedicated to the public domain; its name is a trademark. No Japanese Contemporary Bible (JCB) text is included. No original archive CSS, keys or other bundled files are included.

See [the complete source, extraction, limitations and record contract](../../../docs/scripture-corpus.md). `manifest.json` contains exact source/output hashes, source/license URLs, extraction policy, counts, excluded source books, unsupported source coordinates and missing/empty verses. Literal-source verification does not confer editorial/translation/theological review.

Restore for the guarded local importer, without network, the original archive or Python:

```sh
node scripts/scripture-corpus.mjs verify-bundled
node scripts/scripture-corpus.mjs restore-bundled
```

These commands verify the code-pinned manifest hash and decompressed output hashes. They do not repeat the original XML parse. To independently reparse the exact publisher XML, retain the source archive with its pinned digest and run `prepare`/`verify` as documented.

Gzip uses level 9, no filename and `mtime=0`. Total bundled data is approximately 1.69 MB. Uncompressed NDJSON hashes are in the manifest. Exact compressed hashes:

```text
verses.ndjson.gz      072fee7d215bc8d2af9ca29c6daf29a0108427508d45ed865d46c054b88f86ba
unversified.ndjson.gz ecb7165709541bcfd654a98726f74ae686d45f5a100c64c7b578e474587278d0
```

Recreate the compressed files only from successfully verified prepared artifacts:

```python
import gzip
from pathlib import Path

source = Path('.cache/scripture/prepared')
target = Path('data/scripture/webp-2026-10-13')
for name in ('verses.ndjson', 'unversified.ndjson'):
    with (target / (name + '.gz')).open('wb') as stream:
        with gzip.GzipFile(filename='', mode='wb', fileobj=stream, compresslevel=9, mtime=0) as compressed:
            compressed.write((source / name).read_bytes())
```

Retained counts: 66 books, 31,103 numbered source records, 31,095 nonempty coordinate-compatible records and 138 separate unversified sections. ROM 14:24–26 are unsupported; five note-only markers stay empty; canonical ROM 16:26–27 stay absent. Do not silently remap, fill or represent unavailable verses as complete.
