"""用临时应用包和替代系统校验测试发布流程；ZIP 创建与解压使用真实 ditto。"""
import importlib.util
import json
from pathlib import Path
import plistlib
import os
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('release_package', PROJECT / 'Scripts/package_release.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ReleasePackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.app = self.root / 'build/TaskView.app'
        (self.app / 'Contents/MacOS').mkdir(parents=True)
        (self.app / 'Contents/MacOS/TaskView').write_bytes(b'test executable; not a product build')
        info = {'CFBundleIdentifier': 'com.zhuzhongqian.taskview', 'CFBundleExecutable': 'TaskView',
                'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1', 'LSMinimumSystemVersion': '14.0'}
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        (self.root / 'Docs').mkdir()
        for name in ['安装说明.md', '隐私说明.md']:
            shutil.copyfile(PROJECT / 'Docs' / name, self.root / 'Docs' / name)
        self.signature = 'Authority=TaskView Local Signer\n'
        self.failed = None
        self.original_run = module.run
        self.root_patch = patch.object(module, 'ROOT', self.root)
        self.run_patch = patch.object(module, 'run', side_effect=self.fake_system)
        self.root_patch.start()
        self.run_patch.start()

    def tearDown(self):
        self.run_patch.stop()
        self.root_patch.stop()
        self.temporary.cleanup()

    def fake_system(self, args, capture=False, env=None):
        command = str(args[0])
        if command == 'codesign':
            if self.failed == 'codesign':
                raise RuntimeError('test: signature verification failed')
            return subprocess.CompletedProcess(args, 0, stdout='', stderr=self.signature)
        if command == 'lipo':
            return subprocess.CompletedProcess(args, 0, stdout='arm64\n', stderr='')
        if command in ('spctl', 'xcrun'):
            if self.failed == command:
                raise RuntimeError('test: notarization validation failed')
            return subprocess.CompletedProcess(args, 0, stdout='', stderr='')
        if command == 'hdiutil':
            if self.failed == 'hdiutil':
                raise RuntimeError('test: disk image service unavailable')
            if str(args[1]) == 'create':
                Path(args[-1]).write_bytes(b'test disk image; native DMG creation is not exercised')
            return subprocess.CompletedProcess(args, 0, stdout='', stderr='')
        return self.original_run(args, capture=capture, env=env)

    def test_beta_zip_contents_manifest_and_hash(self):
        output = module.package(self.app, 'beta', True, False)
        manifest = json.loads((output / 'release-manifest.json').read_text())
        self.assertFalse(manifest['notarization_validated'])
        archive = next(output.glob('*.zip'))
        self.assertEqual(manifest['artifacts_sha256'][archive.name], module.digest(archive))
        with zipfile.ZipFile(archive) as stream:
            # ditto 的部分 ZIP 条目使用 UTF-8 文件名但未设 UTF-8 标志；Finder 原生解压可识别。
            names = [item.filename if item.flag_bits & 0x800 else item.filename.encode('cp437').decode('utf-8')
                     for item in stream.infolist()]
            self.assertTrue(any(name.endswith('/TaskView.app/Contents/MacOS/TaskView') for name in names))
            self.assertTrue(any(name.endswith('/安装说明.md') for name in names))
            self.assertTrue(any(name.endswith('/隐私说明.md') for name in names))
            self.assertFalse(any('/Scripts/' in name or name.endswith('.key') for name in names))
        self.assertIn('未经过 Apple 公证', (output / 'RELEASE_NOTES.md').read_text())
        with self.assertRaisesRegex(RuntimeError, '已存在'):
            module.package(self.app, 'beta', True, False)
        self.assertTrue(archive.exists())

    def test_failure_does_not_publish_partial_release(self):
        self.failed = 'hdiutil'
        with self.assertRaises(RuntimeError):
            module.package(self.app, 'beta', False, True)
        self.assertFalse((self.root / 'dist').exists())
        self.assertTrue(self.app.exists())

    def test_reject_unsigned_private_material_and_non_notarized_stable(self):
        self.signature = 'Signature=adhoc\n'
        with self.assertRaisesRegex(RuntimeError, '禁止临时签名'):
            module.package(self.app, 'beta', True, False)
        self.signature = 'Authority=TaskView Local Signer\n'
        with self.assertRaisesRegex(RuntimeError, 'Developer ID'):
            module.package(self.app, 'stable', True, False)
        (self.app / 'Contents/secret.key').write_text('test fixture')
        with self.assertRaisesRegex(RuntimeError, '凭据'):
            module.package(self.app, 'beta', True, False)
        self.assertFalse((self.root / 'dist').exists())

    def test_stable_requires_ticket_validation(self):
        self.signature = 'Authority=Developer ID Application: Test\nflags=0x10000(runtime)\n'
        self.failed = 'xcrun'
        with self.assertRaises(RuntimeError):
            module.package(self.app, 'stable', True, False)
        self.failed = None
        output = module.package(self.app, 'stable', True, False)
        self.assertTrue(json.loads((output / 'release-manifest.json').read_text())['notarization_validated'])

    def test_gitignore_excludes_local_signer_and_generated_files(self):
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        shutil.copyfile(PROJECT / '.gitignore', self.root / '.gitignore')
        for name in ['Scripts/signing/dev.key', 'Scripts/signing/dev.crt', 'dist/file.zip',
                     'build/TaskView.app', '.mimocode/.cron-lock', '.env', 'secret.p12']:
            result = subprocess.run(['git', '-C', str(self.root), 'check-ignore', name], capture_output=True)
            self.assertEqual(result.returncode, 0, name)

    def test_new_developer_generates_own_signer_without_overwriting(self):
        # 钥匙串命令用替代程序隔离；OpenSSL 真实生成和解析临时证书，不访问用户钥匙串。
        scripts = self.root / 'Scripts'
        scripts.mkdir()
        shutil.copyfile(PROJECT / 'Scripts/install_local_signer.sh', scripts / 'install_local_signer.sh')
        tools = self.root / 'tools'
        tools.mkdir()
        security = tools / 'security'
        security.write_text('#!/bin/sh\nexit 0\n')
        security.chmod(0o700)
        env = os.environ.copy()
        env['PATH'] = str(tools) + os.pathsep + env['PATH']
        env['TMPDIR'] = str(self.root)
        command = ['bash', str(scripts / 'install_local_signer.sh')]
        subprocess.run(command, env=env, capture_output=True, check=True)
        cert = scripts / 'signing/dev.crt'
        key = scripts / 'signing/dev.key'
        before = (module.digest(cert), module.digest(key))
        details = subprocess.run(['openssl', 'x509', '-in', str(cert), '-noout', '-text'],
                                 capture_output=True, text=True, check=True).stdout
        self.assertIn('Code Signing', details)
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        subprocess.run(command, env=env, capture_output=True, check=True)
        self.assertEqual(before, (module.digest(cert), module.digest(key)))
        cert.unlink()
        result = subprocess.run(command, env=env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before[1], module.digest(key))


if __name__ == '__main__':
    unittest.main()
