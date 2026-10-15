"""Mutation checks prove that dangerous data regressions are rejected."""
import copy
import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('data_gate', Path(__file__).with_name('validate-data.py'))
gate = importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)


class DataGateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = json.loads((gate.RESOURCE / 'entity-profiles.json').read_text())
        cls.counts = json.loads((gate.RESOURCE / 'verse-counts.json').read_text())

    def rejects(self, mutate):
        document = copy.deepcopy(self.source); mutate(document)
        with self.assertRaises(ValueError): gate.validate(document, self.counts)

    def test_duplicate_identity(self):
        self.rejects(lambda d: d['profiles'].append(d['profiles'][0]))

    def test_missing_license(self):
        self.rejects(lambda d: d['sources'][0].update(license=''))

    def test_wrong_verse(self):
        self.rejects(lambda d: d['occurrences'][0].update(verse=999))

    def test_missing_source(self):
        self.rejects(lambda d: d['profiles'][0].update(sourceIds=['missing']))

    def test_wrong_wikipedia_identity(self):
        self.rejects(lambda d: next(p['wikipedia'] for p in d['profiles'] if p.get('wikipedia')).update(identityVerified=False))

    def test_impossible_coordinate(self):
        self.rejects(lambda d: next(p for p in d['profiles'] if p.get('coordinate')).update(coordinate=[91, 0]))

    def test_bundled_data(self):
        self.assertGreater(gate.validate(self.source, self.counts)['profiles'], 0)
