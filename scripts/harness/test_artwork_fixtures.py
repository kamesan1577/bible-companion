import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('artwork_fixtures', Path(__file__).with_name('seed-artwork-fixtures.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ArtworkFixtureTests(unittest.TestCase):
    def test_actual_museum_bytes_and_unrelated_files_are_preserved(self):
        images = module.verified_images()
        self.assertEqual(len(images), 3)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'unrelated').write_bytes(b'unchanged')
            self.assertEqual(module.seed(root, images), 3)
            for key, data in images.items():
                self.assertEqual((root / module.NAMESPACE / key).read_bytes(), data)
            self.assertEqual((root / 'unrelated').read_bytes(), b'unchanged')
            hashes = json.loads((root / module.NAMESPACE / 'manifest.json').read_text())
            self.assertEqual(hashes, {key: hashlib.sha256(data).hexdigest() for key, data in images.items()})

    def fixture_copy(self, root):
        target = Path(root) / 'images'
        shutil.copytree(module.FIXTURES, target)
        return target / 'manifest.json'

    def test_corrupted_real_image_is_rejected_before_seeding(self):
        with tempfile.TemporaryDirectory() as root:
            manifest = self.fixture_copy(root)
            image = manifest.parent / json.loads(manifest.read_text())['images'][0]['file']
            data = bytearray(image.read_bytes()); data[-1] ^= 1; image.write_bytes(data)
            with self.assertRaisesRegex(ValueError, 'pinned hash'):
                module.verified_images(manifest)
            self.assertFalse((Path(root) / module.NAMESPACE).exists())

    def test_changed_url_or_rights_cannot_silently_relabel_image(self):
        for field, value in [('url', 'https://images.metmuseum.org/different.jpg'), ('rights', 'unreviewed'), ('attribution', 'different work'), ('rightsURL', 'https://invalid.example/'), ('objectURL', 'https://invalid.example/other')]:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as root:
                manifest = self.fixture_copy(root); data = json.loads(manifest.read_text())
                data['images'][0][field] = value; manifest.write_text(json.dumps(data))
                with self.assertRaisesRegex(ValueError, 'unchanged catalog'):
                    module.verified_images(manifest)

    def test_source_path_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            manifest = self.fixture_copy(root); data = json.loads(manifest.read_text())
            data['images'][0]['file'] = '../outside.jpg'; manifest.write_text(json.dumps(data))
            with self.assertRaisesRegex(ValueError, 'escapes'):
                module.verified_images(manifest)

    def test_symlink_target_cannot_replace_unrelated_data(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); victim = root / 'unrelated'; victim.write_bytes(b'keep')
            cache = root / module.NAMESPACE; cache.mkdir(); key = 'a' * 64 + '.image'
            (cache / key).symlink_to(victim)
            with self.assertRaisesRegex(ValueError, 'symlink'):
                module.seed(root, {key: b'new'})
            self.assertEqual(victim.read_bytes(), b'keep')

    def test_non_hash_destination_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaisesRegex(ValueError, 'SHA-256'):
                module.seed(root, {'../outside': b'new'})
            self.assertFalse((Path(root) / module.NAMESPACE).exists())

    def test_mismatched_record_cannot_query_another_device(self):
        with tempfile.TemporaryDirectory() as root:
            record = Path(root) / 'device.json'; record.write_text(json.dumps({'udid': 'other'}))
            with patch.object(module.subprocess, 'check_output') as query:
                with self.assertRaisesRegex(ValueError, 'ownership/reservation'):
                    module.group_for_device('00000000-0000-4000-8000-000000000001', root, record)
                query.assert_not_called()

    def test_group_outside_recorded_device_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); device = '00000000-0000-4000-8000-000000000001'
            record = root / 'device.json'; record.write_text(json.dumps({'udid': device}))
            app = root / 'App'; app.mkdir()
            with (app / 'Info.plist').open('wb') as stream:
                plistlib.dump({'CFBundleIdentifier': 'org.example.BibleCompanion', 'AppGroupIdentifier': 'group.fixture'}, stream)
            wrong = root / 'Devices' / '00000000-0000-4000-8000-000000000002' / 'data/Containers/Shared/AppGroup/fixture'
            wrong.mkdir(parents=True)
            with patch.object(module.subprocess, 'check_output', return_value='group.fixture\t' + str(wrong)):
                with self.assertRaisesRegex(ValueError, 'recorded Simulator'):
                    module.group_for_device(device, app, record)


if __name__ == '__main__':
    unittest.main()
