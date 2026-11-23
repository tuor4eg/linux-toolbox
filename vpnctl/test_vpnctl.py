#!/usr/bin/env python3
"""nmcli failure must not look like "no active VPN". No routes are changed."""
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).with_name('vpnctl')
loader = SourceFileLoader('vpnctl_under_test', str(SOURCE))
spec = importlib.util.spec_from_loader(loader.name, loader)
v = importlib.util.module_from_spec(spec)
loader.exec_module(v)

UUID = '00000000-0000-0000-0000-000000000000'


class NmcliErrors(unittest.TestCase):
    def test_missing_nmcli_is_an_error(self):
        with patch.object(v, 'run', side_effect=FileNotFoundError(2, 'No such file', 'nmcli')):
            with self.assertRaisesRegex(RuntimeError, 'nmcli не найден'):
                v.active_uuids()

    def test_failed_nmcli_is_not_an_empty_vpn_set(self):
        proc = SimpleNamespace(returncode=1, stdout='', stderr='NetworkManager is not running')
        with patch.object(v, 'run', return_value=proc):
            with self.assertRaisesRegex(RuntimeError, 'nmcli:'):
                v.active_uuids()

    def test_failed_nmcli_without_stderr_still_raises(self):
        proc = SimpleNamespace(returncode=1, stdout='', stderr='')
        with patch.object(v, 'run', return_value=proc):
            with self.assertRaisesRegex(RuntimeError, 'не удалось получить список подключений'):
                v.active_uuids()

    def test_no_active_vpn_is_an_empty_set(self):
        proc = SimpleNamespace(returncode=0, stdout='abc:802-11-wireless\n', stderr='')
        with patch.object(v, 'run', return_value=proc):
            self.assertEqual(v.active_uuids(), set())

    def test_active_vpn_uuids_are_kept(self):
        proc = SimpleNamespace(
            returncode=0,
            stdout=UUID + ':vpn\n' + 'wifi:802-11-wireless\n',
            stderr='',
        )
        with patch.object(v, 'run', return_value=proc):
            self.assertEqual(v.active_uuids(), {UUID})

    def test_status_does_not_treat_missing_nmcli_as_disconnected(self):
        cfg = {'profiles': {'work': {
            'uuid': UUID,
            'endpoint': 'auto',
            'expected_networks': ['10.0.0.0/24'],
        }}}
        with patch('sys.argv', ['vpnctl', 'status']), \
             patch.object(v, 'load', return_value=cfg), \
             patch.object(v, 'run', side_effect=FileNotFoundError(2, 'No such file', 'nmcli')), \
             patch.object(v, 'active_proxy', side_effect=AssertionError('must not inspect routes')), \
             patch.object(v, 'apply_one', side_effect=AssertionError('must not change routes')):
            code = v.main()
        self.assertEqual(code, 1)

    def test_apply_stops_before_route_changes_when_nmcli_fails(self):
        cfg = {'profiles': {'work': {
            'uuid': UUID,
            'endpoint': '198.51.100.10',
            'expected_networks': ['10.0.0.0/24'],
        }}}
        proc = SimpleNamespace(returncode=1, stdout='', stderr='nmcli failed')
        with patch('sys.argv', ['vpnctl', 'apply']), \
             patch.object(v, 'load', return_value=cfg), \
             patch.object(v, 'run', return_value=proc), \
             patch.object(v, 'apply_one', side_effect=AssertionError('must not change routes')), \
             patch.object(v, 'sync_network_rules', side_effect=AssertionError('must not change rules')):
            code = v.main()
        self.assertEqual(code, 1)


if __name__ == '__main__':
    unittest.main(verbosity=2)
