#!/usr/bin/env python3
"""Source/configuration checks only. This does not compile or render an iOS app."""
import json
import pathlib
import plistlib
import subprocess
import sys

IOS = pathlib.Path(__file__).resolve().parents[1]
ROOT = IOS.parents[1]
checks = []
def check(name, value):
    if not value:
        raise AssertionError(name)
    checks.append(name)

for filename in ["books.json", "verse-counts.json"]:
    value = json.loads((IOS / "Sources/Core/Resources" / filename).read_text())
    check(f"66-book metadata: {filename}", len(value) == 66)
check("canonical verse counts match backend", json.loads((IOS / "Sources/Core/Resources/verse-counts.json").read_text()) == json.loads((ROOT / "packages/core/src/verse-counts.json").read_text()))
for name in ["material-answer", "ai-policy", "me", "import", "conversation", "reading", "question-result", "model-catalog", "content-manifest", "export-snapshot", "export-page", "comparison-start", "comparison-step", "comparison-expired", "comparison-cancelled-before-start", "conversation-list", "comparison-list", "conversation-detail", "reading-data-deleted", "account-deleted", "scripture-page", "scripture-unavailable", "reading-primary-text"]:
    local = json.loads((IOS / "Tests/Fixtures" / f"{name}.json").read_text())
    server = json.loads((ROOT / "docs/fixtures" / f"{name}.json").read_text())
    check(f"server fixture synchronized: {name}", local == server)
check("reviewed material fixtures synchronized", json.loads((IOS / "Tests/Fixtures/materials.json").read_text()) == json.loads((ROOT / "packages/core/fixtures/source-cards.json").read_text()))
app = plistlib.loads((IOS / "Config/App-Info.plist").read_bytes())
share = plistlib.loads((IOS / "Config/Share-Info.plist").read_bytes())
check("custom callback scheme", app["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == ["biblecompanion"])
check("HTTPS placeholder only", app["APIBaseURL"] == "$(BIBLE_API_URL)" and "NSAppTransportSecurity" not in app)
check("minimal App Group only", all(plistlib.loads((IOS / "Config" / name).read_bytes()) == {"com.apple.security.application-groups": ["$(BIBLE_APP_GROUP)"]} for name in ["App.entitlements", "Share.entitlements"]))
check("narrow share activation", share["NSExtension"]["NSExtensionAttributes"]["NSExtensionActivationRule"] == {"NSExtensionActivationSupportsText": True, "NSExtensionActivationSupportsWebURLWithMaxCount": 1})
for file in (IOS / "Config").rglob("*.xcprivacy"):
    check(f"privacy manifest: {file.parent.name}", plistlib.loads(file.read_bytes())["NSPrivacyTracking"] is False)
sources = list((IOS / "Sources").rglob("*.swift")) + list((IOS / "ShareExtension").glob("*.swift"))
joined = "\n".join(f.read_text() for f in sources)
check("native UI, no web wrapper", not any(word in joined for word in ["WKWebView", "UIWebView", "SFSafariViewController"]))
check("no extension app auto-launch", "UIApplication" not in (IOS / "ShareExtension/ShareViewController.swift").read_text())
check("map never requests user location", not any(word in joined for word in ["CLLocationManager", "requestWhenInUseAuthorization", "requestAlwaysAuthorization", "UserAnnotation(", "MapUserLocationButton("]))
check("no location usage entitlement", not any(key.startswith("NSLocation") for key in app))
check("no credential logging", not any(word in joined for word in ["print(", "debugPrint(", "NSLog("]))
check("iOS26 project", "iOS: '26.0'" in (IOS / "project.yml").read_text())
subprocess.run(["node", str(ROOT / "scripts/design/check-design.mjs")], cwd=ROOT, check=True)
try:
    from tree_sitter import Language, Parser
    import tree_sitter_swift
except ImportError:
    syntax = "not run (optional tree-sitter and tree-sitter-swift packages unavailable)"
else:
    parser = Parser(Language(tree_sitter_swift.language()))
    files = [IOS / "Package.swift"] + list((IOS / "Tests").rglob("*.swift")) + sources
    for file in files:
        tree = parser.parse(file.read_bytes())
        check(f"syntax tree: {file.relative_to(IOS)}", not tree.root_node.has_error)
    syntax = f"parsed {len(files)} Swift files; no syntax errors (NOT type checking)"
print(json.dumps({"source_checks_passed": len(checks), "syntax": syntax, "ios_build": "NOT RUN", "ios_rendering": "NOT RUN", "checks": checks}, ensure_ascii=False, indent=2))
