"""Attach four independently reviewed canonical-place edges without duplicate cards."""
from pathlib import Path
import copy, hashlib, json, datetime

n = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
review_path = n / 'reviews/root-independent-canonical-alias-contexts.json'
review = json.loads(review_path.read_text())
proposal_path = n / review['inputPath']
assert sha(proposal_path) == review['inputSHA256']
proposal = json.loads(proposal_path.read_text())
accepted = {r['entityID']: r for r in review['records'] if r['decision'] == 'pass-limited-canonical-alias-context'}
dest = n / 'reviewed-alias-runtime-preview'
dest.mkdir(exist_ok=True)
counts = {}
for book in ['1CH', '2CH']:
    source = n / 'reviewed-context-runtime-preview' / ('entity-profiles-' + book + '.json')
    catalog = json.loads(source.read_text())
    profiles = {p['id']: p for p in catalog['profiles']}
    sources = {s['id']: s for s in catalog['sources']}
    edges = {(e['entityID'], e['chapter'], e['verse']): e for e in catalog['occurrences']}
    if book == '1CH':
        for item in proposal['candidateCanonicalProfiles']:
            eid = item['entityID']
            q = copy.deepcopy(item['candidateProfile'])
            assert hashlib.sha256((json.dumps(q, ensure_ascii=False, indent=2) + '\n').encode()).hexdigest() == accepted[eid]['candidateProfileSHA256']
            assert eid not in profiles
            assert q['coordinate'] is None
            mapping = {s['id']: 'canonical-alias-' + book + '-' + eid.replace(':', '-') + '-' + s['id'] for s in item['sources']}
            for old in item['sources']:
                s = copy.deepcopy(old)
                s['id'] = mapping[s['id']]
                assert s['id'] not in sources
                sources[s['id']] = s
            for obj in [q] + q['facts']:
                obj['sourceIds'] = [mapping[sid] for sid in obj['sourceIds']]
            if q.get('wikipedia'):
                q['wikipedia']['sourceId'] = mapping[q['wikipedia']['sourceId']]
            alias = next(a for a in proposal['sourceBoundAliases'] if a['canonicalID'] == eid)
            gate = {k: alias['gate'][k] for k in ['chapter', 'verse']}
            q['names'] = [{'nameJa': alias['displayJa'] + '（' + q['nameJa'] + '）', 'knownBy': gate}]
            if eid == 'place:kiriath-jearim_701':
                # Only the independently reviewed narrative view is activated.
                # The earlier genealogical raw profile remains preserved/held.
                container = copy.deepcopy(q)
                container['passages'] = []
                container['contextProfiles'] = [q]
                profiles[eid] = container
            else:
                profiles[eid] = q
            for edge in accepted[eid]['selectedEdges']:
                key = (eid, edge['chapter'], edge['verse'])
                assert key not in edges
                edges[key] = {'entityID': eid, 'chapter': edge['chapter'], 'verse': edge['verse'], 'directlyNamed': edge['relationship'] == 'direct'}
        for alias in proposal['sourceBoundAliases']:
            assert alias['aliasID'] not in profiles
            catalog.setdefault('sourceBoundAliases', []).append({'aliasID': alias['aliasID'], 'canonicalID': alias['canonicalID'], 'knownBy': {k: alias['gate'][k] for k in ['chapter', 'verse']}})
    catalog.update(profiles=list(profiles.values()), sources=list(sources.values()), occurrences=[edges[k] for k in sorted(edges)])
    path = dest / ('entity-profiles-' + book + '.json')
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    counts[book] = {'catalogEntries': len(profiles), 'occurrences': len(edges), 'catalogSHA256': sha(path), 'inputSHA256': sha(source)}
report = {'atUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'scope': 'Four exact source-reviewed canonical-place edges; verse-gated alternate display names; two duplicate raw identities suppressed; earlier 701 genealogy remains held; zero map coordinates approved.', 'reviewSHA256': sha(review_path), 'proposalSHA256': sha(proposal_path), 'books': counts, 'appResourcesWritten': False, 'publicationApproved': False}
(dest / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
