import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('owned', Path(__file__).with_name('create-ios-simulator.py'))
owned = importlib.util.module_from_spec(spec); spec.loader.exec_module(owned)


class OwnedDeviceTests(unittest.TestCase):
    def document(self):
        return {'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-26-0': [{
            'name': 'iPhone 17 Pro', 'isAvailable': True, 'state': 'Booted',
            'udid': '11111111-1111-4111-8111-111111111111',
            'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'}]}}

    def test_booted_peer_is_only_a_template_never_a_target(self):
        new = '22222222-2222-4222-8222-222222222222'
        with patch.object(owned.subprocess, 'check_output', return_value=new+'\n') as command:
            self.assertEqual(owned.create(self.document()), new)
        args = command.call_args.args[0]
        self.assertEqual(args[:3], ['xcrun', 'simctl', 'create'])
        self.assertNotIn('11111111-1111-4111-8111-111111111111', args)
        self.assertEqual(args[-2:], ['com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro', 'com.apple.CoreSimulator.SimRuntime.iOS-26-0'])

    def test_booted_other_model_does_not_change_screenshot_profile(self):
        document = self.document()
        document['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-0'][0]['state'] = 'Shutdown'
        document['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-0'].append({
            'name':'iPhone SE (3rd generation)', 'isAvailable':True, 'state':'Booted',
            'udid':'33333333-3333-4333-8333-333333333333',
            'deviceTypeIdentifier':'com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation'})
        self.assertEqual(owned.template(document)[0], 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro')

    def test_missing_type_fails_without_mutating_any_device(self):
        document = self.document(); document['devices']['com.apple.CoreSimulator.SimRuntime.iOS-26-0'][0].pop('deviceTypeIdentifier')
        with patch.object(owned.subprocess, 'check_output') as command:
            with self.assertRaises(ValueError): owned.create(document)
            command.assert_not_called()

    def test_xcode_destination_preserves_simctl_uuid_case(self):
        identifier = 'AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE'
        with patch.object(owned.subprocess, 'check_output', return_value=identifier+'\n'):
            self.assertEqual(owned.create(self.document()), identifier)
