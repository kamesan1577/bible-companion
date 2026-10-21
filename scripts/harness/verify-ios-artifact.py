#!/usr/bin/env python3
"""Verify a simulator .app or existing IPA without signing, uploading or extracting ZIPs."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[2]


def verify(read, names):
    def require(value, message):
        if not value: raise ValueError(message)
    app = plistlib.loads(read('Info.plist'))
    extension = plistlib.loads(read('PlugIns/BibleShare.appex/Info.plist'))
    project = (ROOT / 'apps/ios/project.yml').read_text()
    version = re.search(r'MARKETING_VERSION: (\S+)', project)[1]
    build = re.search(r'CURRENT_PROJECT_VERSION: (\S+)', project)[1]
    for info, prefix in [(app, ''), (extension, 'PlugIns/BibleShare.appex/')]:
        require(info['CFBundleShortVersionString'] == version and str(info['CFBundleVersion']) == build, 'Artifact version/build differs from this checkout')
        require(int(info['MinimumOSVersion'].split('.')[0]) >= 26, 'Unexpected minimum iOS')
        executable = info['CFBundleExecutable']
        require('/' not in executable and executable not in ['', '.', '..'], 'Invalid executable path')
        binary = read(prefix + executable)
        require(binary[:4] in [b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'], 'Missing Mach-O executable')
    require(extension['CFBundleIdentifier'] == app['CFBundleIdentifier'] + '.Share', 'Extension bundle ID mismatch')
    require(extension['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.share-services', 'Not a Share Extension')
    require('PrivacyInfo.xcprivacy' in names and 'PlugIns/BibleShare.appex/PrivacyInfo.xcprivacy' in names, 'Missing privacy manifests')
    resources = ROOT / 'apps/ios/Sources/Core/Resources'
    # Verify every bundled data/license file, including all commentary books, against this checkout.
    verified = 0
    for path in sorted(resources.iterdir()):
        if not path.is_file(): continue
        matches = [n for n in names if n.endswith('/' + path.name)]
        require(any(not n.startswith('PlugIns/') for n in matches), 'Missing main app resource: ' + path.name)
        require(any(n.startswith('PlugIns/BibleShare.appex/') for n in matches), 'Missing Share Extension resource: ' + path.name)
        expected = hashlib.sha256(path.read_bytes()).hexdigest()
        for name in matches:
            require(hashlib.sha256(read(name)).hexdigest() == expected, 'Resource differs: ' + name)
        verified += 1
    return {'bundleID': app['CFBundleIdentifier'], 'version': version, 'build': build,
            'verifiedResourceFiles': verified, 'shareExtension': True,
            'signingAndDeviceAcceptance': 'not established by this check'}


def inspect(path):
    if path.is_dir() and path.suffix == '.app':
        names = [p.relative_to(path).as_posix() for p in path.rglob('*') if p.is_file()]
        return verify(lambda name: (path / name).read_bytes(), names)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(set(names)) != len(names): raise ValueError('Duplicate ZIP path')
        if any(n.startswith('/') or '..' in Path(n).parts or '\\' in n for n in names):
            raise ValueError('Unsafe ZIP path')
        apps = [n for n in names if re.fullmatch(r'Payload/[^/]+\.app/Info.plist', n)]
        if len(apps) != 1: raise ValueError('Expected exactly one top-level IPA app')
        prefix = apps[0].removesuffix('Info.plist')
        info = plistlib.loads(archive.read(apps[0]))
        if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
            raise ValueError('IPA must contain an iPhoneOS product, not a simulator app')
        result = verify(lambda name: archive.read(prefix + name), [n[len(prefix):] for n in names if n.startswith(prefix)])
        result['artifactSHA256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('artifact', type=Path); args = p.parse_args()
    try: print(json.dumps(inspect(args.artifact), indent=2))
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as e: p.exit(1, str(e) + '\n')
