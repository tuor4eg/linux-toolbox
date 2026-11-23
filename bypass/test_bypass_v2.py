#!/usr/bin/env python3
"""Offline safety tests for bypass-v2. No routes are modified."""
import importlib.util
from importlib.machinery import SourceFileLoader
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).with_name('bypass')
loader = SourceFileLoader('bypass_under_test', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
b = importlib.util.module_from_spec(spec)
loader.exec_module(b)


class Safety(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.patchers = [patch.object(b, 'STATE', Path(self.tmp.name) / 'state.json')]
        for p in self.patchers:
            p.start()
            self.addCleanup(p.stop)
        self.settings = {'gateway': '192.0.2.1', 'dev': 'eth0', 'table': '7113', 'priority': '800',
                         'protected': [b.ipaddress.IPv4Network('10.20.0.0/16')],
                         'servers': {'198.51.100.10'}}
        self.blank = {'version': 1, 'routes': {}, 'rules': {}}

    def test_protected_range_and_server(self):
        with patch.object(b, 'active_openvpn_endpoints', return_value=set()):
            for ip in ('10.20.1.2/32', '10.0.0.0/8', '198.51.100.10/32', '127.0.0.1/32'):
                with self.subTest(ip=ip):
                    with self.assertRaises(RuntimeError):
                        b.validate([ip], self.settings)
            b.validate(['203.0.113.4/32'], self.settings)

    def test_foreign_rule_not_adopted(self):
        with patch.object(b, 'exact_rules', return_value=['800: from all to 203.0.113.4 lookup main']):
            with self.assertRaisesRegex(RuntimeError, 'чужое'):
                b.ensure_rule(self.blank, '203.0.113.4/32', '800')

    def test_foreign_route_not_replaced(self):
        route = {'dst': '203.0.113.4', 'gateway': '192.0.2.1', 'dev': 'eth0'}
        with patch.object(b, 'exact_routes', return_value=[route]):
            with self.assertRaisesRegex(RuntimeError, 'чужой'):
                b.ensure_route(self.blank, '7113', '203.0.113.4/32', self.settings)

    def test_gateway_change_only_owned(self):
        state = {'version': 1, 'routes': {'7113|203.0.113.4/32': {'gateway': '192.0.2.1', 'dev': 'eth0'}}, 'rules': {}}
        new_settings = dict(self.settings, gateway='192.0.2.254', dev='wlan0')
        cmds = []
        def fake(*args, **kw):
            cmds.append(args)
            return SimpleNamespace(returncode=0, stdout='', stderr='')
        with patch.object(b, 'exact_routes', return_value=[{'dst': '203.0.113.4', 'gateway': '192.0.2.1', 'dev': 'eth0'}]), patch.object(b, 'command', side_effect=fake):
            b.ensure_route(state, '7113', '203.0.113.4/32', new_settings)
        self.assertEqual(state['routes']['7113|203.0.113.4/32']['dev'], 'wlan0')
        self.assertTrue(any('replace' in cmd for cmd in cmds))

    def test_do_not_delete_route_modified_externally(self):
        state = {'version': 1, 'routes': {'main|203.0.113.4/32': {'gateway': '192.0.2.1', 'dev': 'eth0'}}, 'rules': {}}
        with patch.object(b, 'exact_routes', return_value=[{'dst': '203.0.113.4', 'gateway': '192.0.2.99', 'dev': 'eth0'}]):
            with self.assertRaisesRegex(RuntimeError, 'изменён извне'):
                b.delete_owned_route(state, 'main', '203.0.113.4/32')

    def test_delete_foreign_rule_is_noop(self):
        with patch.object(b, 'command', side_effect=AssertionError('must not call ip')):
            b.delete_owned_rule(self.blank, '203.0.113.4/32')

    def test_gateway_selection_rejects_vpn(self):
        defaults = [{'dst': 'default', 'gateway': '10.0.0.1', 'dev': 'tun0', 'metric': 10}]
        def fake(*args, **kw):
            return SimpleNamespace(returncode=0, stdout=json.dumps(defaults), stderr='')
        with patch.object(b, 'POLICY', Path(self.tmp.name) / 'missing.json'), patch.object(b, 'command', side_effect=fake):
            with self.assertRaisesRegex(RuntimeError, 'физический'):
                b.policy_and_gateway()

    def test_gateway_selection_chooses_main(self):
        defaults = [{'dst': 'default', 'gateway': '192.0.2.1', 'dev': 'eth0', 'metric': 100}]
        def fake(*args, **kw):
            return SimpleNamespace(returncode=0, stdout=json.dumps(defaults), stderr='')
        with patch.object(b, 'POLICY', Path(self.tmp.name) / 'missing.json'), patch.object(b, 'command', side_effect=fake):
            self.assertEqual(b.policy_and_gateway()['gateway'], '192.0.2.1')

    def test_legacy_conflict_aborts_before_writes(self):
        data = {'203.0.113.4/32': ['203.0.113.4/32']}
        with patch.object(b, 'active_openvpn_endpoints', return_value=set()), patch.object(b, 'direct_docker', return_value=False), patch.object(b, 'exact_routes', return_value=[{'dst': '203.0.113.4', 'gateway': '192.0.2.1', 'dev': 'eth0'}]), patch.object(b, 'command', side_effect=AssertionError('no mutating commands')):
            with self.assertRaisesRegex(RuntimeError, 'унаследованный'):
                b.apply(data, set(), self.settings, self.blank)


if __name__ == '__main__':
    unittest.main(verbosity=2)
