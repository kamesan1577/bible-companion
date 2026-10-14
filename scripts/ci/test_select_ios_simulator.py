import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("selector", Path(__file__).with_name("select-ios-simulator.py"))
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)
ID_A = "00000000-0000-4000-8000-000000000026"
ID_B = "00000000-0000-4000-8000-000000000027"


def device(identifier=ID_A, name="iPhone 17 Pro", available=True, state="Shutdown"):
    return {"udid": identifier, "name": name, "isAvailable": available, "state": state}


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_available_phone_and_ignores_old_runtime(self):
        doc = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-0": [device(ID_B)], "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [device()]}}
        self.assertEqual(selector.select_device(doc), ID_A)

    def test_prefers_phone_over_tablet(self):
        doc = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [device(), device(ID_B, "iPad Pro")]}}
        self.assertEqual(selector.select_device(doc), ID_A)

    def test_prefers_newer_runtime_then_booted_device(self):
        doc = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-0": [device()], "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [device(), device(ID_B, state="Booted")]}}
        self.assertEqual(selector.select_device(doc), ID_B)

    def test_rejects_unavailable_or_malformed_identifiers(self):
        doc = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [device(available=False), device("not-a-uuid"), device(ID_B)]}}
        self.assertEqual(selector.select_device(doc), ID_B)

    def test_never_falls_back_to_old_ios_or_non_ios(self):
        doc = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-0": [device()], "com.apple.CoreSimulator.SimRuntime.tvOS-26-0": [device()]}}
        with self.assertRaisesRegex(ValueError, "No available iOS 26"):
            selector.select_device(doc)

    def test_invalid_document_is_actionable(self):
        with self.assertRaisesRegex(ValueError, "devices object"):
            selector.select_device({})


if __name__ == "__main__":
    unittest.main()
