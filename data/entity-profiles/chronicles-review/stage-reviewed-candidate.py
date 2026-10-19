"""Activate a reversible reviewed subset in the isolated candidate checkout."""
from pathlib import Path
import json, hashlib, datetime, sys

n = Path(__file__).resolve().parent
c = n / 'candidate'
resources = c / 'apps/ios/Sources/Core/Resources'
inputs = []
for book in ['1CH', '2CH']:
    p = n / (sys.argv[1] if len(sys.argv) > 1 else 'reviewed-context-runtime-preview') / ('entity-profiles-' + book + '.json')
    d = json.loads(p.read_text())
    d['editingDisclosureJa'] = '公開原典に基づくAI日本語編集です。歴代誌の一部の人物・地名を対象に、原文と表示開始節を照合しています。全登場名・全節の注解は未完了です。'
    d['verification'] = {'publication': 'unpublished-candidate', 'allNamedEntitiesComplete': False,
                         'allVerseCommentaryComplete': False, 'sourceWitnessVersion': 'webp-usfx-2026-10-13-35a6adf626e5',
                         'unresolvedProfilesExcluded': True, 'newVerifiedCoordinates': 0}
    target = resources / p.name
    target.write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n')
    (resources / (book.lower() + '-map-policy.json')).write_text('[]\n')
    inputs.append({'inputPath': str(p.relative_to(n)), 'inputSHA256': hashlib.sha256(p.read_bytes()).hexdigest(),
                   'candidatePath': str(target.relative_to(c)), 'candidateSHA256': hashlib.sha256(target.read_bytes()).hexdigest(),
                   'catalogEntries': len(d['profiles']), 'occurrences': len(d['occurrences'])})
p = c / 'apps/ios/Sources/Core/BundledEntityIndex.swift'
s = p.read_text()
old = '"1SA", "2SA", "1KI", "2KI"'
new = old + ', "1CH", "2CH"'
assert s.count(old) == 3
if new not in s:
    s = s.replace(old, new)
    p.write_text(s)
report = {'atUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'scope': 'Isolated candidate checkout only; no publication checkout or distribution changed.',
          'inputs': inputs, 'candidateAppResourcesActivated': True,
          'productionAppResourcesActivated': False, 'publicationApproved': False}
(n / 'reviews/root-isolated-candidate-resource-stage.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
