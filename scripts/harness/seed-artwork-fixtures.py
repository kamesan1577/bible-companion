#!/usr/bin/env python3
"""Seed verified actual museum JPEGs only into an explicitly recorded Simulator."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / 'fixtures/artwork'
CATALOG = ROOT / 'apps/ios/UITests/Fixtures/artwork-catalog.json'
NAMESPACE = 'HarnessPublicArtworkFixtures'


def verified_images(manifest=FIXTURES / 'manifest.json', catalog=CATALOG):
    manifest, catalog = Path(manifest), Path(catalog)
    document = json.loads(manifest.read_text())
    if document.get('version') != 1 or not document.get('images'):
        raise ValueError('Unknown or empty artwork fixture manifest')
    cards = {x['id']: x for x in json.loads(catalog.read_text())}
    result = {}
    for image in document['images']:
        candidate = manifest.parent / image['file']
        source = candidate.resolve()
        if source.parent != manifest.parent.resolve() or candidate.is_symlink():
            raise ValueError('Fixture path escapes its directory')
        card = cards[image['id']]
        media = card['details']['media']
        expected = {'url': media['url'], 'rights': media['rights'], 'rightsURL': media['rightsUrl'], 'attribution': media['attribution'], 'objectURL': card['details']['objectUrl']}
        if any(image[key] != value for key, value in expected.items()):
            raise ValueError('Fixture provenance must match the unchanged catalog')
        if source.stat().st_size > 8_000_000:
            raise ValueError('Artwork fixture exceeds the image byte limit')
        data = source.read_bytes()
        if not data.startswith(b'\xff\xd8') or not 0 < len(data) <= 8_000_000:
            raise ValueError('Expected a bounded actual JPEG fixture')
        if hashlib.sha256(data).hexdigest() != image['sha256']:
            raise ValueError('Artwork fixture bytes do not match their pinned hash')
        key = hashlib.sha256(image['url'].encode()).hexdigest() + '.image'
        if key in result:
            raise ValueError('Duplicate artwork fixture URL')
        result[key] = data
    return result


def seed(group, images):
    if any(not re.fullmatch(r'[0-9a-f]{64}\.image', key) for key in images):
        raise ValueError('Fixture keys must be SHA-256 image names')
    directory = Path(group) / NAMESPACE
    if directory.is_symlink():
        raise ValueError('Fixture directory cannot be a symlink')
    # Validate every destination before making any write; never touch private files.
    if (directory / 'manifest.json').is_symlink() or any((directory / key).is_symlink() for key in images):
        raise ValueError('Fixture target cannot be a symlink')
    directory.mkdir(exist_ok=True)
    payloads = dict(images)
    payloads['manifest.json'] = json.dumps({key: hashlib.sha256(data).hexdigest() for key, data in images.items()}, sort_keys=True).encode()
    for key, data in payloads.items():
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as handle:
            handle.write(data)
            temporary = Path(handle.name)
        try:
            os.replace(temporary, directory / key)
        finally:
            temporary.unlink(missing_ok=True)
    return len(images)


def group_for_device(device, app, ownership):
    uuid.UUID(device)
    record = json.loads(Path(ownership).read_text())
    if record.get('udid') != device:
        raise ValueError('Device does not match the harness ownership/reservation record')
    with (Path(app) / 'Info.plist').open('rb') as handle:
        info = plistlib.load(handle)
    output = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, info['CFBundleIdentifier'], 'groups'], text=True)
    groups = dict(line.split('\t', 1) for line in output.splitlines() if '\t' in line)
    root = Path(groups[info['AppGroupIdentifier']]).resolve(strict=True)
    expected = ('Devices', device, 'data', 'Containers', 'Shared', 'AppGroup')
    if not any(tuple(root.parts[i:i + len(expected)]) == expected for i in range(len(root.parts))):
        raise ValueError('App Group is not inside the recorded Simulator')
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--ownership', required=True, type=Path)
    args = parser.parse_args()
    images = verified_images()
    group = group_for_device(args.device, args.app, args.ownership)
    print(json.dumps({'verifiedMuseumImageFixtures': seed(group, images), 'namespace': NAMESPACE}))


if __name__ == '__main__':
    main()
