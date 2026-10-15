import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('jobs', Path(__file__).resolve().parents[1] / 'commentary/codex-jobs.py')
jobs = importlib.util.module_from_spec(spec); spec.loader.exec_module(jobs)


class CheckpointWriteTests(unittest.TestCase):
    def test_interrupted_replace_keeps_prior_packet_and_removes_temp(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'packet.json'
            jobs.write(path, {'accepted': 1})
            with patch.object(jobs.os, 'replace', side_effect=OSError('simulated interrupted save')):
                with self.assertRaises(OSError): jobs.write(path, {'partial': 2})
            self.assertEqual(jobs.read(path), {'accepted': 1})
            self.assertEqual(list(Path(directory).iterdir()), [path])

    def test_success_replaces_complete_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'packet.json'
            jobs.write(path, {'draft': 1}); jobs.write(path, {'draft': 2})
            self.assertEqual(jobs.read(path), {'draft': 2})

    def test_documented_cli_starts_as_script(self):
        result = subprocess.run([sys.executable, str(Path(jobs.__file__)), '--help'],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('prepare,claim,submit,review,export', result.stdout)
