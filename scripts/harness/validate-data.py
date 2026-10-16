#!/usr/bin/env python3
"""Offline structural gate. Semantic truth is evaluated separately; never calls a model."""
import json
import math
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
RESOURCE = ROOT / 'apps/ios/Sources/Core/Resources'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def url(value):
    u = urlparse(value)
    return u.scheme == 'https' and bool(u.hostname) and not u.username and not u.password


def unique(rows, label):
    result = {row['id']: row for row in rows}
    require(len(result) == len(rows), f'duplicate {label} ID')
    return result


def validate(document, counts):
    require(document['schemaVersion'] == 1, 'schema version')
    profiles = unique(document['profiles'], 'profile')
    sources = unique(document['sources'], 'source')
    book = document['scope']['book']

    def verse(v):
        c, n = v['chapter'], v['verse']
        require(type(c) == int and type(n) == int and 1 <= c <= len(counts[book]) and 1 <= n <= counts[book][c-1], 'verse outside canonical range')
        return (c, n)

    def references(ids):
        require(bool(ids) and len(ids) == len(set(ids)) and all(i in sources for i in ids), 'missing or duplicate source reference')

    for source in sources.values():
        require(all(isinstance(source.get(k), str) and source[k].strip() for k in ['title', 'license', 'attribution']), 'source license/attribution')
        require(url(source['url']) and url(source['licenseURL']), 'unsafe source URL')
        if source.get('knownBy'): verse(source['knownBy'])
        if (urlparse(source['url']).hostname or '').endswith('.wikipedia.org'):
            require(source['category'] == 'secondary-reference', 'Wikipedia must remain secondary')
    for profile in profiles.values():
        require(profile['kind'] in ['person', 'place'], 'entity kind')
        require(bool(profile['nameJa']) and bool(profile['summaryJa']), 'missing description')
        verse(profile['knownBy']); references(profile['sourceIds'])
        for passage in profile['passages']:
            require(passage['book'] == book and verse(passage['start']) <= verse(passage['end']), 'profile passage')
        for fact in profile['facts']:
            verse(fact['knownBy']); references(fact['sourceIds'])
        point = profile.get('coordinate')
        if point is not None:
            require(profile['kind'] == 'place' and len(point) == 2 and all(type(x) in [int, float] and math.isfinite(x) for x in point), 'coordinate shape')
            require(-90 <= point[0] <= 90 and -180 <= point[1] <= 180, 'coordinate bounds')
            require(bool(profile.get('locationNoteJa')), 'coordinate uncertainty disclosure')
        wiki = profile.get('wikipedia')
        if wiki:
            parsed = urlparse(wiki['url'])
            require(url(wiki['url']) and parsed.hostname == wiki['language'] + '.wikipedia.org' and parsed.path.startswith('/wiki/'), 'Wikipedia article URL')
            require(wiki.get('identityVerified') is True and bool(wiki.get('checkedAt')) and bool(wiki.get('noteJa')), 'Wikipedia identity evidence')
    seen = set()
    for occurrence in document['occurrences']:
        require(occurrence['entityID'] in profiles, 'unknown occurrence identity')
        position = verse(occurrence)
        key = (occurrence['entityID'], position)
        require(key not in seen, 'duplicate occurrence'); seen.add(key)
        require(type(occurrence['directlyNamed']) == bool, 'explicit vs context identity flag')
    return {'profiles': len(profiles), 'sources': len(sources), 'occurrences': len(seen),
            'scope': book, 'semanticAcceptance': 'not established by structural validation'}


if __name__ == '__main__':
    document = json.loads((RESOURCE / 'entity-profiles.json').read_text())
    counts = json.loads((RESOURCE / 'verse-counts.json').read_text())
    print(json.dumps(validate(document, counts), ensure_ascii=False, indent=2))
