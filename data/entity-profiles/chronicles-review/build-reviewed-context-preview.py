"""Attach only exact independently reviewed contexts to an isolated preview."""
from pathlib import Path
import copy, hashlib, json, datetime, sys

n = Path(__file__).resolve().parent
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
proposal = n / 'reviews/context-edits/1CH/context-variants-gad-ephraim-israel.json'
review_path = n / 'reviews/root-independent-context-variants-current.json'
review = json.loads(review_path.read_text())
assert sha(proposal) == review['inputSHA256']
accepted = {r['entityID']: r for r in review['records']
            if r['decision'] == 'pass-primary-text-only-context'}
raw = json.loads(proposal.read_text())
dest = n / 'reviewed-context-runtime-preview'
dest.mkdir(exist_ok=True)
counts = {}
for book in ['1CH', '2CH']:
    source = n / (sys.argv[1] if len(sys.argv) > 1 else 'conservative-runtime-preview') / ('entity-profiles-' + book + '.json')
    catalog = json.loads(source.read_text())
    profiles = {p['id']: p for p in catalog['profiles']}
    sources = {s['id']: s for s in catalog['sources']}
    occurrences = {(e['entityID'], e['chapter'], e['verse']): e for e in catalog['occurrences']}
    placeholder_ids = []
    contexts = 0
    if book == '1CH':
        for item in raw['contextVariants']:
            eid = item['entityID']
            assert eid in accepted
            assert item['candidateProfileSHA256'] == accepted[eid]['candidateProfileSHA256']
            q = copy.deepcopy(item['candidateProfileOverlay']['contextProfiles'][0])
            mapping = {s['id']: 'ctx-' + book + '-' + eid.replace(':', '-') + '-' + s['id']
                       for s in item['sources']}
            for s in item['sources']:
                normalized = copy.deepcopy(s)
                normalized['id'] = mapping[s['id']]
                assert normalized['id'] not in sources
                sources[normalized['id']] = normalized
            for obj in [q] + q['facts']:
                obj['sourceIds'] = [mapping[sid] for sid in obj['sourceIds']]
            # A qualified collective base is not silently activated. A copy of
            # the reviewed individual supplies the required catalog container;
            # its empty base passages cannot resolve as a displayed base.
            assert eid not in profiles
            container = copy.deepcopy(q)
            container['passages'] = []
            container['contextProfiles'] = [q]
            profiles[eid] = container
            placeholder_ids.append(eid)
            contexts += 1
            for edge in item['sourceCoordinateEdges']:
                key = (eid, edge['chapter'], edge['verse'])
                assert key not in occurrences
                occurrences[key] = {'entityID': eid, 'chapter': edge['chapter'],
                                    'verse': edge['verse'], 'directlyNamed': edge['relationship'] == 'direct'}
    catalog.update(profiles=list(profiles.values()), sources=list(sources.values()),
                   occurrences=[occurrences[k] for k in sorted(occurrences)],
                   sourceBoundAliases=[])
    path = dest / ('entity-profiles-' + book + '.json')
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    counts[book] = {'catalogEntries': len(profiles), 'activeBaseProfiles': len(profiles) - len(placeholder_ids),
                    'individualContexts': contexts, 'individualOnlyContainerIDs': placeholder_ids,
                    'occurrences': len(occurrences), 'catalogSHA256': sha(path),
                    'conservativeInputSHA256': sha(source)}
report = {'atUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'scope': 'Isolated candidate with exact primary-source-reviewed personal contexts. Collective bases and aliases remain held.',
          'proposalSHA256': sha(proposal), 'independentReviewSHA256': sha(review_path),
          'books': counts, 'appResourcesWritten': False, 'publicationApproved': False}
(dest / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
