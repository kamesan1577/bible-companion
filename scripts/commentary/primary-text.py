"""Resolve verified commentary-only alternate versification without changing the corpus."""
import gzip, hashlib, json
from pathlib import Path

def require(condition, message='Invalid commentary primary alignment'):
    if not condition:
        raise ValueError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def resolve(rows, alignment, manifest_bytes, verses_bytes):
    manifest = json.loads(manifest_bytes)
    require(alignment['schemaVersion'] == 1, 'Invalid commentary primary alignment')
    require(alignment['canonicalReferenceSystem'] == 'KJV', 'Invalid commentary primary alignment')
    require(alignment['sourceManifestSha256'] == sha(manifest_bytes), 'Invalid commentary primary alignment')
    require(alignment['sourceCorpusVersion'] == manifest['version'], 'Invalid commentary primary alignment')
    require(alignment['sourceVersesSha256'] == manifest['hash']['verses'] == sha(verses_bytes), 'Invalid commentary primary alignment')
    primary = {f"{r['canonical']['book']}:{r['canonical']['chapter']}:{r['canonical']['verse']}": r['text'] for r in rows if r.get('canonical') and r.get('text')}
    expected = {f'ROM:16:{i}': ('ROM', 14, str(i - 1)) for i in [25, 26, 27]}
    require(len(alignment['alignments']) == 3, 'Invalid commentary primary alignment')
    require({a['canonicalReference'] for a in alignment['alignments']} == set(expected), 'Invalid commentary primary alignment')
    for a in alignment['alignments']:
        ref = a['canonicalReference']
        s = a['sourceReference']
        key = (s['book'], s['chapter'], s['verse'])
        require(key == expected[ref], 'Invalid commentary primary alignment')
        require(ref not in primary, 'Never overwrite a nonempty canonical verse')
        matches = [r for r in rows if (r['sourceBook'], r['sourceChapter'], r['sourceVerse']) == key]
        require(len(matches) == 1, 'Invalid commentary primary alignment')
        row = matches[0]
        require(row['canonical'] is None and row['alignment'] == 'unsupported' and (row['textStatus'] == 'present') and row['text'], 'Invalid commentary primary alignment')
        require(a['sourceTextSha256'] == sha(row['text'].encode()), 'Invalid commentary primary alignment')
        primary[ref] = row['text']
    return primary

def load_primary(root):
    root = Path(root)
    corpus = root / 'data/scripture/webp-2026-10-13'
    raw = gzip.decompress((corpus / 'verses.ndjson.gz').read_bytes())
    rows = [json.loads(l) for l in raw.decode().splitlines()]
    return resolve(rows, json.loads((root / 'data/commentary/primary-alignments.json').read_text()), (corpus / 'manifest.json').read_bytes(), raw)
