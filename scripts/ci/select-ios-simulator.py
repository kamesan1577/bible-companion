#!/usr/bin/env python3
"""Select an available iOS 26+ device from the current Xcode's simctl JSON."""
import json
import re
import sys
import uuid


def select_device(document):
    if not isinstance(document, dict) or not isinstance(document.get("devices"), dict):
        raise ValueError("Expected simctl JSON with a devices object")
    candidates = []
    for runtime, devices in document["devices"].items():
        version = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)(?:-(\d+))?(?:-(\d+))?", runtime)
        if not version or int(version[1]) < 26 or not isinstance(devices, list):
            continue
        parsed_version = tuple(int(part or 0) for part in version.groups())
        for device in devices:
            if not isinstance(device, dict) or device.get("isAvailable") is not True:
                continue
            identifier = device.get("udid")
            name = device.get("name", "")
            if not isinstance(identifier, str) or not isinstance(name, str):
                continue
            try:
                if str(uuid.UUID(identifier)).lower() != identifier.lower():
                    continue
            except ValueError:
                continue
            candidates.append((name.startswith("iPhone"), parsed_version, device.get("state") == "Booted", name, identifier))
    if not candidates:
        raise ValueError("No available iOS 26+ simulator; check installed runtimes for the selected Xcode")
    return max(candidates)[-1]


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("Usage: select-ios-simulator.py SIMCTL_JSON")
        with open(sys.argv[1], encoding="utf-8") as source:
            print(select_device(json.load(source)))
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
