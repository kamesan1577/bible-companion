"""Reversible eligibility preview; never writes app resources or approves content."""
from pathlib import Path
import json, hashlib, datetime, collections

n = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
bindings_path = n / 'reviews/root-current-independent-review-bindings.json'
maps_path = n / 'reviews/root-current-map-independent-bindings.json'
bindings = json.loads(bindings_path.read_text())
maps = json.loads(maps_path.read_text())
future_path = n / 'reviews/root-future-reference-reader-field-audit.json'
future_audit = json.loads(future_path.read_text())
future_holds = {(r['draftPath'], r['draftSHA256']) for r in future_audit['findings']}
reader_path = n / 'reviews/root-additional-reader-field-holds.json'
reader_holds = {(r['book'], r['entityID']) for r in json.loads(reader_path.read_text())['records']}
profiles = {}
for group in bindings['groups'].values():
    for record in group['currentRecords']:
        if not record['bytesMatchIndependentReview']:
            continue
        p = n / record['draftPath']
        assert sha(p) == record['draftSHA256']
        assert sha(n / record['evidencePath']) == record['evidenceSHA256']
        d = json.loads(p.read_text()).get('profile')
        if d:
            key = (Path(record['draftPath']).name[:3], d['id'])
            assert key not in profiles, key
            profiles[key] = (d, record)

# These identities require a separate, coordinate-specific disposition.
context_ids = {'person:gad_1262', 'person:ephraim_1206', 'person:israel_682',
               'place:jabesh_610', 'place:jabesh-gilead_611', 'place:baalah_135',
               'place:kiriath-jearim_701'}
rows = []
for binding in maps['reports']:
    assert binding['reportBindsCurrentMap']
    chunk = binding['chunk']
    mp = n / 'reviews' / ('verse-map-' + chunk + '.json')
    rp = n / binding['reportPath']
    assert sha(mp) == binding['currentMapSHA256']
    assert sha(rp) == binding['reportSHA256']
    m = json.loads(mp.read_text())
    report = json.loads(rp.read_text())
    verdicts = {(r['chapter'], r['verse']): r.get('decision', r.get('verdict'))
                for r in report.get('rows', report.get('verses', []))}
    for verse in m['verses']:
        pos = (verse['chapter'], verse['verse'])
        for edge in verse['entities']:
            key = (m['book'], edge['entityID'])
            pair = profiles.get(key)
            reasons = []
            if key in reader_holds:
                reasons.append('unclosed-root-reader-field-finding')
            if verdicts[pos] != 'pass':
                reasons.append('map-qualified-or-failed')
            if not pair:
                reasons.append('current-reviewed-profile-missing-or-held')
            else:
                profile, record = pair
                if record['decision'] != 'pass':
                    reasons.append('profile-qualified-or-failed')
                if (record['draftPath'], record['draftSHA256']) in future_holds:
                    reasons.append('unclosed-explicit-future-reader-reference')
                gate = profile['knownBy']
                if pos < (gate['chapter'], gate['verse']):
                    reasons.append('before-profile-knownBy')
                if not any(p['book'] == m['book'] and
                           (p['start']['chapter'], p['start']['verse']) <= pos <=
                           (p['end']['chapter'], p['end']['verse'])
                           for p in profile['passages']):
                    reasons.append('outside-profile-passages')
            if edge['entityID'] in context_ids:
                reasons.append('explicit-context-or-alias-disposition-required')
            rows.append({'book': m['book'], 'chapter': pos[0], 'verse': pos[1],
                         'entityID': edge['entityID'], 'relationship': edge['relationship'],
                         'sourceTextSHA256': verse['sourceTextSHA256'],
                         'citationURL': verse['citationURL'], 'holds': reasons,
                         'profileInputBinding': pair[1] if pair else None,
                         'mechanicallyEligibleForFurtherReview': not reasons})
out = {'atUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
       'scope': 'Conservative source-edge preview only; pass is necessary but not sufficient for runtime activation. Qualified cases remain held.',
       'inputSHA256': {str(p.relative_to(n)): sha(p) for p in [bindings_path, maps_path, future_path, reader_path]},
       'reviewedActiveProfiles': len(profiles), 'mappedEdges': len(rows),
       'furtherReviewCandidateEdges': sum(not r['holds'] for r in rows),
       'holdReasons': dict(collections.Counter(x for r in rows for x in r['holds'])),
       'appResourcesWritten': False, 'semanticApproval': False, 'publicationApproved': False,
       'rows': rows}
(n / 'reviews/root-reviewed-occurrence-edge-preview.json').write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n')
print(json.dumps({k: v for k, v in out.items() if k != 'rows'}))
