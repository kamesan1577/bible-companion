"""Derive source-only candidates from exact independently reviewed dispositions.

No authored prose is changed, no qualified review is promoted to pass, and no
application resource is written. All Wikipedia links are withheld in this stage.
"""
from pathlib import Path
import copy, hashlib, json, collections, datetime

n = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
reports = [
    'runtime-disposition-qualified-persons1-b01-b05.json',
    'runtime-disposition-qualified-persons2-b01-b04-current.json',
    'runtime-disposition-qualified-persons2-b05-current.json',
    'runtime-disposition-qualified-persons3-b01-b04.json',
    'runtime-disposition-batch05-persons_3-qualified.json',
    'runtime-disposition-batch06-persons_1-qualified.json',
    'root-reader-five-primary-disposition-delta.json',
    'runtime-disposition-batch06-persons_3-qualified.json',
    'root-projected-reader-concrete-runtime-delta.json',
    'runtime-disposition-primary-context-citations-delta.json',
    'root-sibbechai-rationale-reclosure-delta.json',
    'runtime-disposition-batch06-persons_2-qualified.json',
    'runtime-disposition-batch07-persons_1-qualified.json',
    'root-projected-tahan-current-delta.json',
    'root-projected-shelomith-reader-note-delta.json',
]
reports.extend(['projected-runtime-disposition-primary-qualified-batch07-persons_2.json', 'projected-runtime-disposition-batch07-persons_3-qualified-primary-only.json', 'projected-runtime-disposition-primary-qualified-batch08-persons_1.json', 'projected-runtime-disposition-batch08-persons_3-qualified.json', 'projected-runtime-disposition-batch09-persons_1-qualified-pending.json', 'projected-runtime-disposition-batch09-persons_3-qualified.json', 'projected-ishi626-evidence-only-delta.json', 'projected-hiram1533-root-repair-delta.json', 'projected-qualified-runtime-disposition-batch08-persons_2-current-rebind.json', 'projected-qualified-runtime-disposition-batch08-persons_2-conaniah-current-delta.json'])
reports.append('projected-god1324-primary-only-current.json')
reports.extend(['runtime-disposition-batch09-persons_2-after-independent-repairs.json','projected-extension-independent-runtime-disposition-ben-hadad-452-current-batch08-persons_3.json', 'projected-resume-six-and-shobal-qualified.json'])
reports.append('projected-resume-three-links-qualified.json')
assert len(reports)==len(set(reports)), "Duplicate disposition report input"
dispositions = {}
report_inputs = {}
for name in reports:
    path = n / 'reviews' / name
    report_inputs[str(path.relative_to(n))] = sha(path)
    data = json.loads(path.read_text())
    for row in data.get('rows', data.get('records', [])):
        key = (row['book'], row['entityID'])
        if key in dispositions:
            assert name in ['root-reader-five-primary-disposition-delta.json', 'root-projected-reader-concrete-runtime-delta.json', 'runtime-disposition-primary-context-citations-delta.json', 'root-projected-tahan-current-delta.json', 'root-projected-shelomith-reader-note-delta.json', 'projected-ishi626-evidence-only-delta.json', 'projected-extension-independent-runtime-disposition-ben-hadad-452-current-batch08-persons_3.json', 'projected-resume-six-and-shobal-qualified.json', 'projected-resume-three-links-qualified.json']
            assert row['draftPath'] == dispositions[key]['draftPath']
        dispositions[key] = row

edge_path = n / 'reviews/root-reviewed-occurrence-edge-preview.json'
edge_data = json.loads(edge_path.read_text())
for path, expected in edge_data['inputSHA256'].items():
    assert sha(n / path) == expected
ledger_path = n / 'normalized-staging/ledger.json'
ledger = {(r['book'], r['id']): r for r in json.loads(ledger_path.read_text())}
dest = n / 'qualified-primary-runtime-preview'
dest.mkdir(exist_ok=True)
decisions = []
counts = {}
for book in ['1CH', '2CH']:
    base_path = n / 'conservative-runtime-preview' / ('entity-profiles-' + book + '.json')
    catalog = json.loads(base_path.read_text())
    source_path = n / 'normalized-staging' / ('entity-profiles-' + book + '.json')
    staging = json.loads(source_path.read_text())
    source_lookup = {s['id']: s for s in staging['sources']}
    profiles = {p['id']: p for p in catalog['profiles']}
    sources = {s['id']: s for s in catalog['sources']}
    edges = {(e['entityID'], e['chapter'], e['verse']): e for e in catalog['occurrences']}
    for profile in staging['profiles']:
        key = (book, profile['id'])
        row = dispositions.get(key)
        if not row:
            continue
        reasons = []
        raw_disposition = row.get('runtimeDisposition', row.get('primaryOnlyDisposition'))
        disposition = {'primary-only': 'primary-only-display-supported', 'related-link': 'related-link-supported'}.get(raw_disposition, raw_disposition)
        if disposition not in ['primary-only-display-supported', 'related-link-supported']:
            reasons.append('independent-disposition-held')
        binding = ledger[key]
        expected_draft = row.get('currentDraftSHA256', row.get('draftSHA256'))
        expected_evidence = row.get('currentEvidenceSHA256', row.get('evidenceSHA256'))
        if binding['input'] != row['draftPath'] or binding['sha256'] != expected_draft or sha(n / row['draftPath']) != expected_draft or sha(n / row['evidencePath']) != expected_evidence:
            reasons.append('stale-disposition-binding')
        # Only a qualified profile disposition may be replaced; all source-map,
        # context, first-use, passage and explicit-future holds remain effective.
        eligible = [e for e in edge_data['rows'] if (e['book'], e['entityID']) == key and e['holds'] == ['profile-qualified-or-failed'] and e['profileInputBinding']['decision'] in ['qualified', 'pending']]
        if not eligible:
            reasons.append('no-independently-eligible-map-edge')
        p = copy.deepcopy(profile)
        # A primary-only derivation cannot retain authored assertions explicitly
        # attributed to an article or translation comparison with no such source.
        # This is a conservative hold trigger, not a semantic correctness test.
        reader_text = ' '.join(str(p.get(k) or '') for k in ['nameJa', 'subtitleJa', 'summaryJa', 'identityNoteJa', 'historicalRoleJa', 'modernLocationJa', 'locationNoteJa'])
        if any(term in reader_text for term in ['記事', '英語版', '他の訳', '異表記', '英語資料', '別表記', '割当', '候補表記', '候補名']):
            reasons.append('secondary-dependent-reader-prose-requires-separate-disposition')
        p['wikipedia'] = None
        for obj in [p] + p['facts']:
            obj['sourceIds'] = [sid for sid in obj['sourceIds'] if source_lookup[sid]['category'] == 'primary-text']
            if not obj['sourceIds']:
                reasons.append('reader-field-without-primary-source')
        if p.get('contextProfiles'):
            reasons.append('unreviewed-context-profile')
        if p.get('coordinate') is not None:
            reasons.append('coordinates-require-separate-review')
        decisions.append({'book': book, 'entityID': p['id'], 'draftPath': row['draftPath'], 'draftSHA256': expected_draft, 'evidencePath': row['evidencePath'], 'evidenceSHA256': expected_evidence, 'independentRuntimeDisposition': disposition, 'retainedReviewDecision': eligible[0]['profileInputBinding']['decision'] if eligible else row.get('overallReviewDecision', 'qualified'), 'derivedWikipediaDisposition': 'withheld-including-related-links', 'holds': sorted(set(reasons)), 'selectedEdges': len(eligible) if not reasons else 0})
        if reasons:
            continue
        assert p['id'] not in profiles
        positions = sorted({(e['chapter'], e['verse']) for e in eligible})
        p['passages'] = [{'book': book, 'start': {'chapter': c, 'verse': v}, 'end': {'chapter': c, 'verse': v}} for c, v in positions]
        profiles[p['id']] = p
        for obj in [p] + p['facts']:
            for sid in obj['sourceIds']:
                sources[sid] = source_lookup[sid]
        for e in eligible:
            ek = (p['id'], e['chapter'], e['verse'])
            assert ek not in edges
            edges[ek] = {'entityID': p['id'], 'chapter': e['chapter'], 'verse': e['verse'], 'directlyNamed': e['relationship'] == 'direct'}
    catalog.update(profiles=list(profiles.values()), sources=list(sources.values()), occurrences=[edges[k] for k in sorted(edges)])
    path = dest / ('entity-profiles-' + book + '.json')
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    counts[book] = {'profiles': len(profiles), 'occurrences': len(edges), 'catalogSHA256': sha(path), 'baseInputSHA256': sha(base_path), 'stagingInputSHA256': sha(source_path)}
report = {'atUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'scope': 'Exact-bound independently source-supported Japanese descriptions only. Qualified decisions retained. All secondary links withheld for additions; all other edge holds retained. No prose changes.', 'inputSHA256': dict(report_inputs, **{str(edge_path.relative_to(n)): sha(edge_path), str(ledger_path.relative_to(n)): sha(ledger_path)}), 'books': counts, 'qualifiedAdditions': sum(not r['holds'] for r in decisions), 'holdReasons': dict(collections.Counter(x for r in decisions for x in r['holds'])), 'decisions': decisions, 'appResourcesWritten': False, 'publicationApproved': False}
(dest / 'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in report.items() if k != 'decisions'}))
