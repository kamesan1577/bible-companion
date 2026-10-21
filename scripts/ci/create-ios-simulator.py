#!/usr/bin/env python3
"""Create an owned device from an installed iOS 26+ template; never reuse a booted device."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import uuid

spec = importlib.util.spec_from_file_location('selector', Path(__file__).with_name('select-ios-simulator.py'))
selector = importlib.util.module_from_spec(spec); spec.loader.exec_module(selector)


def template(document):
    identifier = selector.select_device(document)
    runtime = next(r for r, devices in document['devices'].items() if any(d.get('udid') == identifier for d in devices))
    preferred = [d for d in document['devices'][runtime] if d.get('isAvailable') is True and d.get('deviceTypeIdentifier') == 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro']
    if not preferred:
        raise ValueError('UI screenshot fixtures require an available iPhone 17 Pro in the latest iOS runtime')
    identifier = sorted(preferred, key=lambda d: d['udid'])[0]['udid']
    for runtime, devices in document['devices'].items():
        for device in devices:
            if device.get('udid') == identifier:
                kind = device.get('deviceTypeIdentifier')
                if not isinstance(kind, str) or not kind.startswith('com.apple.CoreSimulator.SimDeviceType.'):
                    raise ValueError('Installed template has no deviceTypeIdentifier')
                return kind, runtime
    raise ValueError('Selected template missing')


def create(document):
    kind, runtime = template(document)
    name = 'BibleHarness-' + str(uuid.uuid4())[:8]
    result = subprocess.check_output(['xcrun', 'simctl', 'create', name, kind, runtime], text=True).strip()
    print(json.dumps({'ownedSimulator': result, 'deviceType': kind, 'runtime': runtime}), file=sys.stderr, flush=True)
    uuid.UUID(result)  # Validate without changing case: Xcode destination matching preserves it.
    return result


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2: raise ValueError('Usage: create-ios-simulator.py SIMCTL_JSON')
        print(create(json.loads(Path(sys.argv[1]).read_text())))
    except (ValueError, OSError, subprocess.CalledProcessError) as e:
        print(str(e), file=sys.stderr); sys.exit(1)
