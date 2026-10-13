"""验证采样工具的时间和进程输出解析，不把替代数据当成实测性能。"""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('profile_idle', Path(__file__).resolve().parents[1] / 'Scripts/profile_idle.py')
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class ProfileIdleTests(unittest.TestCase):
    def test_cpu_time_formats(self):
        self.assertAlmostEqual(profile.seconds('0:01.23'), 1.23)
        self.assertEqual(profile.seconds('02:03:04'), 7384)
        self.assertEqual(profile.seconds('1-02:03:04'), 93784)
        with self.assertRaises(ValueError):
            profile.seconds('unexpected')

    def test_process_units(self):
        result = subprocess.CompletedProcess([], 0, stdout='123 20480 0:01.23 01:00\n', stderr='')
        with patch.object(profile.subprocess, 'run', return_value=result):
            sample = profile.read_process(123)
        self.assertEqual(sample['pid'], 123)
        self.assertEqual(sample['rss_mib'], 20)
        self.assertAlmostEqual(sample['cpu_seconds'], 1.23)
        self.assertEqual(sample['process_age_seconds'], 60)

    def test_missing_process_and_access_failure(self):
        for result in [subprocess.CompletedProcess([], 1, stdout='', stderr=''),
                       subprocess.CompletedProcess([], 1, stdout='', stderr='Operation not permitted')]:
            with patch.object(profile.subprocess, 'run', return_value=result), self.assertRaises(RuntimeError):
                profile.read_process(123)


if __name__ == '__main__':
    unittest.main()
