"""Build an isolated, reviewable catalog from the conservative edge preview.

This writes no application resource. It is not publication eligibility approval.
"""
from pathlib import Path
import json, hashlib, datetime, collections

n = Path(__file__).resolve().parent
edge_path = n / 'reviews/root-reviewed-occurrence-edge-preview.json'
edge_data = json.loads(edge_path.read_text())
ledger_path = n / 'normalized-staging/ledger.json'
ledger = {(r['book'], r['id']): r for r in json.loads(ledger_path.read_text())}
for path, expected in edge_data['inputSHA256'].items():
    assert hashlib.sha256((n / path).read_bytes()).hexdigest() == expected
dest = n / 'conservative-runtime-preview'
dest.mkdir(exist_ok=True)
counts = {}
for book in ['1CH', '2CH']:
    source_path = n / 'normalized-staging' / ('entity-profiles-' + book + '.json')
    source = json.loads(source_path.read_text())
    edges = [r for r in edge_data['rows'] if r['book'] == book and not r['holds']]
    positions = collections.defaultdict(set)
    for r in edges:
        binding = r['profileInputBinding']
        item = ledger[book, r['entityID']]
        assert item['input'] == binding['draftPath']
        assert item['sha256'] == binding['draftSHA256']
        assert hashlib.sha256((n / binding['draftPath']).read_bytes()).hexdigest() == binding['draftSHA256']
        assert hashlib.sha256((n / binding['evidencePath']).read_bytes()).hexdigest() == binding['evidenceSHA256']
        positions[r['entityID']].add((r['chapter'], r['verse']))
    profiles = []
    for p in source['profiles']:
        if p['id'] not in positions:
            continue
        # Narrow display spans to independently mapped selected verses.
        # Preserve all authored wording, facts, source gates and identities.
        p = dict(p)
        p['passages'] = [{'book': book, 'start': {'chapter': c, 'verse': v},
                          'end': {'chapter': c, 'verse': v}}
                         for c, v in sorted(positions[p['id']])]
        assert not p.get('contextProfiles')
        profiles.append(p)
    assert {p['id'] for p in profiles} == set(positions)
    needed = set()
    for p in profiles:
        needed.update(p['sourceIds'])
        for fact in p['facts']:
            needed.update(fact['sourceIds'])
        if p.get('wikipedia'):
            needed.add(p['wikipedia']['sourceId']) if 'sourceId' in p['wikipedia'] else None
    sources = [s for s in source['sources'] if s['id'] in needed]
    assert needed <= {s['id'] for s in sources}
    out = {'schemaVersion': 1, 'sources': sources, 'profiles': profiles,
           'occurrences': [{'entityID': r['entityID'], 'chapter': r['chapter'],
                            'verse': r['verse'], 'directlyNamed': r['relationship'] == 'direct'}
                           for r in edges], 'sourceBoundAliases': []}
    path = dest / ('entity-profiles-' + book + '.json')
    path.write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n')
    counts[book] = {'profiles': len(profiles), 'occurrences': len(edges),
                    'sources': len(sources), 'catalogSHA256': hashlib.sha256(path.read_bytes()).hexdigest(),
                    'normalizedInputSHA256': hashlib.sha256(source_path.read_bytes()).hexdigest()}
report = {'atUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'scope': 'Isolated conservative preview; display spans narrowed to selected map edges. No new facts or identity approvals.',
          'edgePreviewSHA256': hashlib.sha256(edge_path.read_bytes()).hexdigest(),
          'normalizationLedgerSHA256': hashlib.sha256(ledger_path.read_bytes()).hexdigest(),
          'books': counts, 'appResourcesWritten': False, 'publicationApproved': False,
          'allNamedEntitiesComplete': False, 'allVerseCommentaryComplete': False}
(dest / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
