import importlib.util
import plistlib
from pathlib import Path
import re
import unittest

spec = importlib.util.spec_from_file_location('artifact_gate', Path(__file__).with_name('verify-ios-artifact.py'))
gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)


class ArtifactGateTests(unittest.TestCase):
    def setUp(self):
        text = (gate.ROOT / 'apps/ios/project.yml').read_text()
        app = {'CFBundleShortVersionString': re.search(r'MARKETING_VERSION: (\S+)', text)[1],
               'CFBundleVersion': re.search(r'CURRENT_PROJECT_VERSION: (\S+)', text)[1],
               'MinimumOSVersion': '26.0', 'CFBundleExecutable': 'App', 'CFBundleIdentifier': 'test.Bible'}
        ext = dict(app, CFBundleIdentifier='test.Bible.Share', CFBundleExecutable='Share',
                   NSExtension={'NSExtensionPointIdentifier': 'com.apple.share-services'})
        self.files = {'Info.plist': plistlib.dumps(app), 'App': b'\xcf\xfa\xed\xfeTEST',
                      'PlugIns/BibleShare.appex/Info.plist': plistlib.dumps(ext),
                      'PlugIns/BibleShare.appex/Share': b'\xcf\xfa\xed\xfeTEST',
                      'PrivacyInfo.xcprivacy': b'', 'PlugIns/BibleShare.appex/PrivacyInfo.xcprivacy': b''}
        self.resources = gate.ROOT / 'apps/ios/Sources/Core/Resources'
        self.names = list(self.files) + ['Core.bundle/' + p.name for p in self.resources.iterdir() if p.is_file()]

    def read(self, name):
        return self.files[name] if name in self.files else (self.resources / Path(name).name).read_bytes()

    def test_matching_resources_and_extension(self):
        self.assertTrue(gate.verify(self.read, self.names)['shareExtension'])

    def test_corrupt_resource_fails(self):
        self.files['Core.bundle/entity-profiles.json'] = b'{}'
        with self.assertRaises(ValueError): gate.verify(self.read, self.names)

    def test_missing_extension_privacy_manifest_fails(self):
        self.names.remove('PlugIns/BibleShare.appex/PrivacyInfo.xcprivacy')
        with self.assertRaises(ValueError): gate.verify(self.read, self.names)

    def test_wrong_bundle_identity_fails(self):
        info = plistlib.loads(self.files['PlugIns/BibleShare.appex/Info.plist'])
        info['CFBundleIdentifier'] = 'other.Share'
        self.files['PlugIns/BibleShare.appex/Info.plist'] = plistlib.dumps(info)
        with self.assertRaises(ValueError): gate.verify(self.read, self.names)
