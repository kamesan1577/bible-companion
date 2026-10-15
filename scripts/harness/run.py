#!/usr/bin/env python3
"""Credential-free development entrypoint; stdlib only, fail on first failure."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / '.cache/harness'


def run(*args, capture=False):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), cwd=ROOT, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def doctor(ios=False):
    for name in ['git', 'node', 'npm', 'python3'] + (['swift', 'xcodebuild', 'xcrun', 'xcodegen'] if ios else []):
        if not shutil.which(name):
            raise ValueError(f'Missing {name}; see docs/harness/README.md')
    major = int(run('node', '-p', 'process.versions.node.split(".")[0]', capture=True).strip())
    if major != 24:
        raise ValueError(f'Use Node 24 LTS (found {major}); no automatic dependency upgrade')
    run('node', '--version'); run('npm', '--version'); run('python3', '--version')
    if ios:
        run('xcodebuild', '-version'); run('xcodegen', '--version')
        sdk = run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version', capture=True).strip()
        if int(sdk.split('.')[0]) < 26:
            raise ValueError('iOS 26+ SDK required')
    print('Doctor passed; no credentials or production service needed.')


def swift_test():
    OUT.mkdir(parents=True, exist_ok=True)
    os.environ['CLANG_MODULE_CACHE_PATH'] = str(OUT / 'clang-modules')
    os.environ['SWIFT_MODULE_CACHE_PATH'] = str(OUT / 'swift-modules')
    run('swift', 'test', '--package-path', 'apps/ios', '--scratch-path', OUT / 'swift',
        '--cache-path', OUT / 'swift-cache', '--config-path', OUT / 'swift-config',
        '--security-path', OUT / 'swift-security', '--jobs', '2')


def data():
    run(sys.executable, 'scripts/harness/validate-data.py')
    for name in ['codex-jobs', 'chapter-contexts', 'review-ledger', 'primary-text']:
        run(sys.executable, f'scripts/commentary/{name}.test.py')
    run(sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/harness', '-p', 'test_*.py')
    run(sys.executable, '-m', 'unittest', 'discover', '-s', 'scripts/ci', '-p', 'test_*.py')


def check():
    doctor()
    temporary = (OUT / 'tmp').resolve()
    temporary.mkdir(parents=True, exist_ok=True)
    os.environ['TMPDIR'] = str(temporary)
    guard = str(ROOT / 'scripts/diagnostics/no-external-network.cjs')
    if guard not in os.environ.get('NODE_OPTIONS', ''):
        os.environ['NODE_OPTIONS'] = (os.environ.get('NODE_OPTIONS', '') + ' --require="' + guard + '"').strip()
    run('npm', 'run', 'validate')
    data()
    run('npm', 'run', 'openapi')
    run('git', 'diff', '--exit-code', '--', 'docs/openapi.json')
    run('npm', 'run', 'migrate'); run('npm', 'run', 'migrate')
    run('npm', 'run', 'infra', '--', 'validate-config')
    run('npm', 'run', 'deploy:dry-run')
    print('Portable checks passed. Run swift and ios-ui separately on Apple toolchains.')


def ios(command, device):
    doctor(ios=True)
    if (ROOT / 'apps/ios/Config/Local.private.xcconfig').exists():
        raise ValueError('Use a clean checkout without Local.private.xcconfig for reproducible unsigned QA')
    run('bash', 'apps/ios/Scripts/generate-project.sh')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    result = OUT / f'{command}-{stamp}'
    result.mkdir(parents=True)
    device_build = command == 'ios-device'
    base = ['xcodebuild', '-jobs', '2', '-project', 'apps/ios/BibleCompanion.xcodeproj',
            '-configuration', 'Release' if device_build else 'Debug',
            '-sdk', 'iphoneos' if device_build else 'iphonesimulator',
            '-derivedDataPath', str(OUT / ('device-derived' if device_build else 'ios-derived')),
            'CODE_SIGNING_ALLOWED=NO']
    if device_build:
        run(*base, '-scheme', 'BibleCompanion', '-destination', 'generic/platform=iOS',
            '-resultBundlePath', result / 'Build.xcresult', 'build')
        app = OUT / 'device-derived/Build/Products/Release-iphoneos/BibleCompanion.app'
        payload = result / 'Payload'
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        archive = result / 'BibleCompanion-unsigned.ipa'
        run('ditto', '-c', '-k', '--keepParent', payload, archive)
        run(sys.executable, 'scripts/harness/verify-ios-artifact.py', archive)
        print(f'Unsigned offline IPA candidate: {archive}; existing signer/SideStore required before installation.')
        return
    if command == 'ios-build':
        run(*base, '-scheme', 'BibleCompanion', '-destination', 'generic/platform=iOS Simulator',
            '-resultBundlePath', result / 'Build.xcresult', 'build')
        app = OUT / 'ios-derived/Build/Products/Debug-iphonesimulator/BibleCompanion.app'
        if not (app / 'PlugIns/BibleShare.appex').is_dir():
            raise ValueError('Share Extension missing from built app')
        run(sys.executable, 'scripts/harness/verify-ios-artifact.py', app)
    else:
        if not device:
            document = run('xcrun', 'simctl', 'list', 'devices', 'available', '--json', capture=True)
            (result / 'simulators.json').write_text(document)
            device = run(sys.executable, 'scripts/ci/select-ios-simulator.py', result / 'simulators.json', capture=True).strip()
        for scheme in ['BibleCompanion', 'ReadingInteractionUI']:
            run(*base, '-scheme', scheme, '-destination', f'platform=iOS Simulator,id={device}',
                '-destination-timeout', '90', '-parallel-testing-enabled', 'NO',
                '-resultBundlePath', result / f'{scheme}.xcresult', 'test')
    print(f'Results: {result}; screenshots are evidence, not visual acceptance.')


def audit_source(ref):
    # Inspect the Git object tree rather than local untracked source or Release ZIPs.
    paths = set(run('git', 'ls-tree', '-r', '--name-only', ref, capture=True).splitlines())
    required = ['package-lock.json', 'apps/ios/project.yml', 'apps/ios/Package.swift',
                'apps/ios/Sources/Core/Resources/entity-profiles.json', 'apps/api/src/index.ts',
                'scripts/commentary/codex-jobs.py', 'scripts/export-source.mjs']
    for path in required:
        if path not in paths:
            raise ValueError(f'Source missing from {ref}: {path}')
    for prefix in ['apps/ios/ShareExtension/', 'apps/ios/UITests/', 'packages/core/', 'packages/ai-harness/']:
        if not any(p.startswith(prefix) for p in paths):
            raise ValueError(f'Missing tracked tree {prefix}')
    for path in paths:
        if (Path(path).name.startswith('.env') and Path(path).name != '.env.example') or path.endswith(('.p12', '.mobileprovision', '.pem', '.key', '.sqlite', '.ipa')) or path.endswith('Local.private.xcconfig'):
            raise ValueError(f'Private path tracked: {path}')
    print(json.dumps({'commit': run('git', 'rev-parse', ref, capture=True).strip(),
                      'trackedFiles': len(paths), 'sourceInGitTree': True}))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['doctor', 'setup', 'check', 'data', 'swift', 'ios-build', 'ios-device', 'ios-ui', 'audit-source'])
    p.add_argument('--ios', action='store_true'); p.add_argument('--device')
    p.add_argument('--ref', default='HEAD')
    a = p.parse_args()
    if a.command == 'doctor': doctor(a.ios)
    elif a.command == 'setup': doctor(); run('npm', 'ci')
    elif a.command == 'check': check()
    elif a.command == 'data': data()
    elif a.command == 'swift': swift_test()
    elif a.command == 'audit-source': audit_source(a.ref)
    else: ios(a.command, a.device)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Harness failed: {error}', file=sys.stderr)
        sys.exit(1)
