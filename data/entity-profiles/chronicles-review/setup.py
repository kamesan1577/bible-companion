#!/usr/bin/env python3
"""Create candidate-only Chronicles1/Chronicles2 inventories from the pinned ROM/LEV input archive.

This preparation step reads but does not copy or edit candidate app source. It does not
write profiles, interpret names, verify index links, or publish anything. Outputs are
write-once: if any output already exists, inspect/resume rather than regenerate.
"""
from __future__ import annotations
import gzip
import hashlib
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE_ROOT = Path('published-source-checkout')
CANDIDATE = SOURCE_ROOT
INDEX_PATH = CANDIDATE / 'apps/ios/Sources/Core/Resources/entity-index.json'
WEB_DIR = CANDIDATE / 'data/scripture/webp-2026-10-13'
WEB_GZIP = WEB_DIR / 'verses.ndjson.gz'
WEB_MANIFEST = WEB_DIR / 'manifest.json'
BOOKS = ('1CH', '2CH')
BOOK_NAMES = {'1CH': '1 Chronicles', '2CH': '2 Chronicles'}
CHAPTER_COUNTS = {'1CH': 29, '2CH': 36}
WITNESS_VERSION = 'webp-usfx-2026-10-13-35a6adf626e5'
EXPECTED_INDEX_SHA = 'dfe6fba1109f192548e28645cf085ddafe3baf7820d200e2e28da486dd98f11a'
EXPECTED_GZIP_SHA = '072fee7d215bc8d2af9ca29c6daf29a0108427508d45ed865d46c054b88f86ba'

OUTPUTS = [
    ROOT / 'inventory/inventory.json', ROOT / 'inventory/source-manifest.json',
    ROOT / 'inventory/chronicles1.json', ROOT / 'inventory/chronicles2.json',
    ROOT / 'inventory/targets.json', ROOT / 'inventory/identity-risks.json',
    ROOT / 'inventory/targets/chronicles1-targets.json', ROOT / 'inventory/targets/chronicles2-targets.json',
    ROOT / 'inventory/targets/chronicles1-web-verses.json', ROOT / 'inventory/targets/chronicles2-web-verses.json',
    ROOT / 'inventory/targets/initial-unverified-occurrences.json',
    *[ROOT / f'assignments/{kind}_{i}.json' for kind in ('persons', 'places') for i in (1, 2, 3)],
    ROOT / 'assignments/manifest.json',
]

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def write_new(path: Path, value) -> None:
    if path.exists():
        raise FileExistsError(f'Refusing to overwrite existing output: {path}')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def decode_code(code: int, book_index: int):
    if code // 1_000_000 != book_index:
        return None
    rem = code % 1_000_000
    return rem // 1_000, rem % 1_000

def citation_url(book: str, chapter: int, verse: int) -> str:
    return f'https://ebible.org/engwebp/{book}{chapter:02d}.htm#V{verse}'

def main() -> None:
    existing = [str(p.relative_to(ROOT)) for p in OUTPUTS if p.exists()]
    if existing:
        raise SystemExit('Existing outputs found; inspection/resume required, no files changed: ' + ', '.join(existing))
    for p in (INDEX_PATH, WEB_GZIP, WEB_MANIFEST):
        if not p.is_file():
            raise SystemExit(f'Required pinned input missing: {p}')
    index_bytes = INDEX_PATH.read_bytes()
    gzip_sha = sha256(WEB_GZIP)
    index_sha = hashlib.sha256(index_bytes).hexdigest()
    if index_sha != EXPECTED_INDEX_SHA or gzip_sha != EXPECTED_GZIP_SHA:
        raise SystemExit(f'Pinned source SHA mismatch: entity-index={index_sha}; WEB gzip={gzip_sha}')
    index = json.loads(index_bytes)
    manifest = json.loads(WEB_MANIFEST.read_text(encoding='utf-8'))
    if manifest.get('version') != WITNESS_VERSION:
        raise SystemExit('Fixed WEB witness version mismatch')
    books = index['books']
    book_indexes = {b: books.index(b) + 1 for b in BOOKS}
    if book_indexes != {'1CH': 13, '2CH': 14}:
        raise SystemExit(f'Unexpected source-index book codes: {book_indexes}')

    verses = {b: [] for b in BOOKS}
    with gzip.open(WEB_GZIP, 'rt', encoding='utf-8') as f:
        for line in f:
            row = json.loads(line)
            if row.get('sourceBook') in verses:
                verses[row['sourceBook']].append(row)
    for b in BOOKS:
        verses[b].sort(key=lambda r: (int(r['sourceChapter']), int(r['sourceVerse'])))
        chapters = sorted({int(r['sourceChapter']) for r in verses[b]})
        if chapters != list(range(1, CHAPTER_COUNTS[b] + 1)):
            raise SystemExit(f'Unexpected chapter coverage for {b}: {chapters}')
        if any(r.get('version') != WITNESS_VERSION for r in verses[b]):
            raise SystemExit(f'Mixed source versions in {b}')
        keys = [(int(r['sourceChapter']), int(r['sourceVerse'])) for r in verses[b]]
        if len(keys) != len(set(keys)):
            raise SystemExit(f'Duplicate source verse coordinate in {b}')

    verse_lookup = {(b, int(r['sourceChapter']), int(r['sourceVerse'])): r for b in BOOKS for r in verses[b]}
    targets = {b: [] for b in BOOKS}
    duplicate_ids = []
    ids_seen = set()
    for ent in index.get('entities', []):
        eid = ent.get('id')
        if eid in ids_seen:
            duplicate_ids.append(eid)
        ids_seen.add(eid)
        kind = ent.get('kind')
        if kind not in ('person', 'place'):
            continue
        for b in BOOKS:
            refs = []
            for raw in ent.get('appearances', []):
                try:
                    code = int(raw)
                except (TypeError, ValueError):
                    continue
                decoded = decode_code(code, book_indexes[b])
                if decoded is None:
                    continue
                ch, verse = decoded
                row = verse_lookup.get((b, ch, verse))
                refs.append({
                    'chapter': ch, 'verse': verse, 'indexCode': code,
                    'relationship': 'unverified-candidate', 'reviewStatus': 'unreviewed',
                    'coordinateStatus': 'matched-to-fixed-WEB-coordinate' if row else 'unmatched-in-fixed-WEB',
                    'candidateText': row.get('text') if row else None,
                    'textStatus': row.get('textStatus', 'present') if row else 'missing-from-fixed-witness',
                })
            if refs:
                refs.sort(key=lambda r: (r['chapter'], r['verse'], r['indexCode']))
                targets[b].append({
                    'book': b, 'targetKey': f'{b}:{eid}', 'id': eid, 'kind': kind,
                    'name': ent.get('name'), 'nameJa': ent.get('nameJa'),
                    'appearances': refs, 'candidateOccurrenceCount': len(refs),
                    'identityVerified': False,
                })
    for b in BOOKS:
        targets[b].sort(key=lambda r: r['id'])

    occurrences = []
    coordinate_audit = {}
    for b in BOOKS:
        all_refs = [dict({'book': b, 'targetKey': t['targetKey'], 'entityID': t['id'], 'kind': t['kind']}, **r) for t in targets[b] for r in t['appearances']]
        occurrences.extend(all_refs)
        unmatched = [r for r in all_refs if r['coordinateStatus'] != 'matched-to-fixed-WEB-coordinate']
        coordinate_audit[b] = {
            'candidateOccurrenceCount': len(all_refs),
            'uniqueCandidateCoordinates': len({(r['chapter'], r['verse']) for r in all_refs}),
            'matchedCoordinateOccurrences': len(all_refs) - len(unmatched),
            'unmatchedCoordinateOccurrences': len(unmatched),
            'unmatchedCoordinates': [{'targetKey': r['targetKey'], 'chapter': r['chapter'], 'verse': r['verse'], 'indexCode': r['indexCode']} for r in unmatched],
            'interpretation': 'Coordinate matching only; no semantic identity or verse-link accuracy review was performed.',
        }

    names = defaultdict(list)
    for b in BOOKS:
        for t in targets[b]:
            if t.get('name'):
                names[t['name']].append({'book': b, 'id': t['id'], 'nameJa': t.get('nameJa')})
    dupnames = [
        {'name': n, 'candidates': rows, 'status': 'unverified-same-name-candidates'}
        for n, rows in sorted(names.items()) if len({r['id'] for r in rows}) > 1
    ]
    special = {}
    for spelling in ('Moses', 'Pharaoh'):
        rows = []
        for b in BOOKS:
            for t in targets[b]:
                if (t.get('name') or '').casefold() == spelling.casefold():
                    rows.append({'book': b, 'targetKey': t['targetKey'], 'id': t['id'], 'nameJa': t.get('nameJa'), 'refs': t['appearances']})
        special[spelling] = {'status': 'unverified-no-identity-adjudication', 'candidateCount': len(rows), 'candidates': rows,
                             'noteJa': '索引の表記と座標候補だけを列挙。個体同定、称号の同一人物化、時代差、代名詞関係は未検証。'}

    assignments = {}
    assignment_summary = {}
    for kind, outkind in (('person', 'persons'), ('place', 'places')):
        recs = [r for b in BOOKS for r in targets[b] if r['kind'] == kind]
        bins = [[] for _ in range(3)]
        weights = [0, 0, 0]
        for rec in sorted(recs, key=lambda r: (-r['candidateOccurrenceCount'], r['book'], r['id'])):
            i = min(range(3), key=lambda j: (weights[j], j))
            bins[i].append(rec); weights[i] += rec['candidateOccurrenceCount']
        for i, rows in enumerate(bins, 1):
            rows.sort(key=lambda r: (r['book'], r['id']))
            assignments[f'{outkind}_{i}'] = rows
            assignment_summary[f'{outkind}_{i}'] = {
                'records': len(rows), 'books': dict(Counter(r['book'] for r in rows)),
                'candidateOccurrenceCount': weights[i-1], 'uniqueBookIdKeys': len({r['targetKey'] for r in rows}) == len(rows),
            }

    book_counts = {}
    for b in BOOKS:
        counts = Counter(int(r['sourceChapter']) for r in verses[b])
        book_counts[b] = {
            'chapterCount': len(counts), 'verseCount': len(verses[b]),
            'nonemptyVerseCount': sum(bool(r.get('text')) for r in verses[b]),
            'perChapterVerseCounts': {str(ch): counts[ch] for ch in sorted(counts)},
            'fixedVersion': WITNESS_VERSION,
            'sourceVerseSHA256': hashlib.sha256(('\n'.join(json.dumps(r, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for r in verses[b])+'\n').encode('utf-8')).hexdigest(),
            'sourceTextEditorialReview': 'unreviewed',
        }

    source_manifest = {
        'sourceWorkspace': str(SOURCE_ROOT),
        'entityIndex': {'path': 'candidate/apps/ios/Sources/Core/Resources/entity-index.json', 'sha256': index_sha,
                        'sourceCommit': index.get('sourceCommit'), 'license': index.get('license'),
                        'readOnlySourcePath': str(INDEX_PATH)},
        'fixedWEB': {'path': 'candidate/data/scripture/webp-2026-10-13/verses.ndjson.gz', 'sha256': gzip_sha,
                     'manifestSHA256': sha256(WEB_MANIFEST), 'version': manifest.get('version'), 'edition': manifest.get('edition'),
                     'license': manifest.get('license'), 'sourceURL': manifest.get('sourceURL'), 'readOnlySourcePath': str(WEB_GZIP)},
        'books': book_counts,
        'extractionSemantics': 'Fixed WEB rows copied literally from source gzip; index appearances decoded only to book/chapter/verse coordinates. No text/entity semantic review, identity verification, or source-code copy.',
    }
    outputs = {
        ROOT/'inventory/source-manifest.json': source_manifest,
        ROOT/'inventory/chronicles1.json': {'book':'1CH','name':BOOK_NAMES['1CH'],'chapterCount':book_counts['1CH']['chapterCount'],'verseCount':book_counts['1CH']['verseCount'],
            'candidateCounts':{'targets':len(targets['1CH']),'persons':sum(t['kind']=='person' for t in targets['1CH']),'places':sum(t['kind']=='place' for t in targets['1CH']),'candidateOccurrenceLinks':sum(t['candidateOccurrenceCount'] for t in targets['1CH'])},'reviewStatus':'candidate inventory only; no identity or occurrence is verified'},
        ROOT/'inventory/chronicles2.json': {'book':'2CH','name':BOOK_NAMES['2CH'],'chapterCount':book_counts['2CH']['chapterCount'],'verseCount':book_counts['2CH']['verseCount'],
            'candidateCounts':{'targets':len(targets['2CH']),'persons':sum(t['kind']=='person' for t in targets['2CH']),'places':sum(t['kind']=='place' for t in targets['2CH']),'candidateOccurrenceLinks':sum(t['candidateOccurrenceCount'] for t in targets['2CH'])},'reviewStatus':'candidate inventory only; no identity or occurrence is verified'},
        ROOT/'inventory/targets.json': {'books':targets,'candidateOnly':True,'recordKey':'(book,id) — the same ID in two books is stored twice'},
        ROOT/'inventory/targets/chronicles1-targets.json':targets['1CH'],
        ROOT/'inventory/targets/chronicles2-targets.json':targets['2CH'],
        ROOT/'inventory/targets/chronicles1-web-verses.json':[
            {'sourceId':r.get('sourceId'),'version':r.get('version'),'sourceBook':r.get('sourceBook'),'sourceChapter':int(r.get('sourceChapter')),'sourceVerse':int(r.get('sourceVerse')),
             'canonical':{'book':'1CH','chapter':int(r.get('sourceChapter')),'verse':int(r.get('sourceVerse'))},'text':r.get('text'),'textStatus':r.get('textStatus','present'),
             'citationURL':citation_url('1CH',int(r.get('sourceChapter')),int(r.get('sourceVerse'))),'alignment':'preserved-from-pinned-fixed-source; not semantically reviewed'} for r in verses['1CH']],
        ROOT/'inventory/targets/chronicles2-web-verses.json':[
            {'sourceId':r.get('sourceId'),'version':r.get('version'),'sourceBook':r.get('sourceBook'),'sourceChapter':int(r.get('sourceChapter')),'sourceVerse':int(r.get('sourceVerse')),
             'canonical':{'book':'2CH','chapter':int(r.get('sourceChapter')),'verse':int(r.get('sourceVerse'))},'text':r.get('text'),'textStatus':r.get('textStatus','present'),
             'citationURL':citation_url('2CH',int(r.get('sourceChapter')),int(r.get('sourceVerse'))),'alignment':'preserved-from-pinned-fixed-source; not semantically reviewed'} for r in verses['2CH']],
        ROOT/'inventory/targets/initial-unverified-occurrences.json': {'status':'unverified-index-links-only','bookCount':2,'occurrenceCount':len(occurrences),'coordinateAudit':coordinate_audit,'occurrences':occurrences},
        ROOT/'inventory/identity-risks.json': {'status':'candidate-only; identity and name semantics unreviewed','sourceIndexSHA256':index_sha,
            'duplicateEntityIDsInSourceIndex':sorted(set(duplicate_ids)),'duplicateNamesAcrossTargetIDs':dupnames,'MosesAndPharaoh':special,
            'globalWarningJa':'すべての候補リンクは未検証。同名の別人、民族・部族・氏族・家系名、称号、役職、地名と人名の混同を含み得る。候補IDを人物の実在・同一性・出現の品質承認とみなさず、草稿を自動生成しない。Moses/Pharaohは特に称号・時代別個体の照合が必要。'},
        ROOT/'assignments/manifest.json': {'books':list(BOOKS),'assignmentKinds':['persons','places'],
            'method':'Greedy load balancing by raw candidate occurrence count within each kind; assignment key is book,id, so same ID in 1CH and 2CH remains two separate records.',
            'assignmentSummary':assignment_summary,'allTargetsAssignedExactlyOnce':True,
            'reviewStatus':'initial assignment only; identity, text links, same-name, collective, title and occurrence semantics are unverified.'},
        ROOT/'inventory/inventory.json': {'books':book_counts,
            'targetsByBook':{b:{'total':len(targets[b]),'persons':sum(t['kind']=='person' for t in targets[b]),'places':sum(t['kind']=='place' for t in targets[b]),'candidateOccurrenceLinks':sum(t['candidateOccurrenceCount'] for t in targets[b])} for b in BOOKS},
            'assignmentSummary':assignment_summary,'source':'inventory/source-manifest.json','coordinateAudit':'inventory/targets/initial-unverified-occurrences.json',
            'identityRisks':'inventory/identity-risks.json; all candidates unverified','generatedBy':'setup.py','generatedAtUTC':datetime.now(timezone.utc).isoformat(),'editorialReview':False},
    }
    for k,v in assignments.items(): outputs[ROOT/f'assignments/{k}.json']=v
    # Confirm every declared output is being created exactly once before writing any file.
    if set(outputs) != set(OUTPUTS):
        missing=sorted(str(p.relative_to(ROOT)) for p in set(OUTPUTS)-set(outputs))
        extra=sorted(str(p.relative_to(ROOT)) for p in set(outputs)-set(OUTPUTS))
        raise SystemExit(f'Output manifest mismatch: missing={missing}; extra={extra}')
    for path,value in outputs.items(): write_new(path,value)
    print(json.dumps({'status':'created','workspace':str(ROOT),'sourceSHA256':{'entityIndex':index_sha,'webGzip':gzip_sha},'bookCounts':book_counts,
        'targets':{b:{'targets':len(targets[b]),'occurrences':coordinate_audit[b]['candidateOccurrenceCount'],'unmatchedCoordinates':coordinate_audit[b]['unmatchedCoordinateOccurrences']} for b in BOOKS},
        'assignments':assignment_summary,'candidateAppSourceCopied':False},ensure_ascii=False,indent=2))

if __name__ == '__main__':
    main()
