#!/usr/bin/env python3
"""编译并打包下载版；只分发应用和用户文档，不上传 GitHub 或包含签名私钥。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(arguments, capture=False, env=None):
    result = subprocess.run([str(argument) for argument in arguments], cwd=ROOT, env=env,
                            text=True, capture_output=capture, check=False)
    if result.returncode:
        details = (result.stderr or result.stdout or '').strip() if capture else ''
        raise RuntimeError(f'命令失败：{arguments[0]}（退出码 {result.returncode}）' + (f'\n{details}' if details else ''))
    return result


def verify(app):
    run(['codesign', '--verify', '--strict', app], capture=True)
    result = run(['codesign', '-dvv', app], capture=True)
    signature = result.stderr + result.stdout
    if 'Signature=adhoc' in signature or 'Authority=' not in signature:
        raise RuntimeError('下载包必须使用证书签名，禁止临时签名或无证书签名。')
    return signature


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def package(app, channel, zip_only, rebuilt):
    if not app.is_dir() or app.is_symlink():
        raise RuntimeError('找不到完整的 build/TaskView.app，请先完成证书签名构建。')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    version = str(info.get('CFBundleShortVersionString', ''))
    build = str(info.get('CFBundleVersion', ''))
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', build):
        raise RuntimeError('应用版本号或构建号无效。')
    if info.get('CFBundleExecutable') != 'TaskView' or info.get('CFBundleIdentifier') != 'com.zhuzhongqian.taskview':
        raise RuntimeError('应用包的名称或 Bundle ID 与本项目不一致。')
    signature = verify(app)
    if channel == 'stable':
        if 'Authority=Developer ID Application:' not in signature or '(runtime)' not in signature:
            raise RuntimeError('正式版需要 Developer ID Application 签名和 Hardened Runtime。')
        run(['xcrun', 'stapler', 'validate', app], capture=True)
        run(['spctl', '--assess', '--type', 'execute', '--verbose=2', app], capture=True)
    binary = app / 'Contents/MacOS/TaskView'
    archs = sorted(run(['lipo', '-archs', binary], capture=True).stdout.split())
    if not archs or not set(archs).issubset({'arm64', 'x86_64'}):
        raise RuntimeError('无法确认支持的 macOS 架构。')
    arch = 'universal' if len(archs) == 2 else archs[0]
    label = f'{version}-beta.{build}' if channel == 'beta' else version
    stem = f'TaskView-{label}-{arch}'
    destination = ROOT / 'dist' / stem
    if destination.exists():
        raise RuntimeError(f'发布目录已存在：{destination}。请增加构建号或先保留、移走旧包。')
    # 防止未来误把开发签名材料放入应用资源；公开证书作为 Mach-O 签名的一部分允许存在。
    for path in app.rglob('*'):
        if path.suffix.lower() in {'.key', '.p12', '.pfx', '.pem'} or (path.is_file() and path.name.startswith('.env')):
            raise RuntimeError(f'应用包包含疑似签名凭据，拒绝打包：{path.relative_to(app)}')
    (ROOT / 'build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='release-package.', dir=ROOT / 'build') as temporary:
        stage = Path(temporary)
        contents = stage / stem
        contents.mkdir()
        copied_app = contents / 'TaskView.app'
        run(['ditto', app, copied_app])
        verify(copied_app)
        for name in ['安装说明.md', '隐私说明.md']:
            shutil.copyfile(ROOT / 'Docs' / name, contents / name)
        (contents / 'Applications').symlink_to('/Applications', target_is_directory=True)
        output = stage / 'output'
        output.mkdir()
        archive = output / (stem + '.zip')
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', contents, archive])
        # 解压并再次验证，确认归档保存了应用结构和签名。
        unpacked = stage / 'unpacked'
        run(['ditto', '-x', '-k', archive, unpacked])
        verify(unpacked / stem / 'TaskView.app')
        for name in ['安装说明.md', '隐私说明.md']:
            if digest(unpacked / stem / name) != digest(contents / name):
                raise RuntimeError('ZIP 解压后用户文档发生变化，拒绝发布。')
        artifacts = [archive]
        if not zip_only:
            image = output / (stem + '.dmg')
            run(['hdiutil', 'create', '-volname', f'TaskView {label}', '-srcfolder', contents,
                 '-format', 'UDZO', '-fs', 'HFS+', image])
            run(['hdiutil', 'verify', image], capture=True)
            artifacts.append(image)
        hashes = {path.name: digest(path) for path in artifacts}
        (output / 'SHA256SUMS.txt').write_text(''.join(f'{value}  {name}\n' for name, value in hashes.items()), encoding='utf-8')
        manifest = {
            'name': 'TaskView', 'version': version, 'build': build, 'channel': channel,
            'architectures': archs, 'minimum_macos': info.get('LSMinimumSystemVersion'),
            'notarization_validated': channel == 'stable',
            'build_origin': 'rebuilt' if rebuilt else 'existing local app; source freshness not asserted',
            'signature_authorities': [line.split('=', 1)[1] for line in signature.splitlines() if line.startswith('Authority=')],
            'artifacts_sha256': hashes,
        }
        (output / 'release-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        notice = '这是未经过 Apple 公证的 Beta 测试版，首次打开可能需要用户按系统提示确认。' if channel == 'beta' else '应用已验证 Developer ID 签名、公证票据及系统执行评估。'
        notes = f'''# TaskView {label}

{notice}

支持 macOS {info.get('LSMinimumSystemVersion')}+；架构：{', '.join(archs)}。

下载 ZIP 或 DMG，将 TaskView.app 移入“应用程序”后打开。无需拉取源码、Xcode、Python或导入证书。首次使用需授予屏幕录制及辅助功能权限。

功能包含可搜索窗口网格、显示器筛选、应用分组、窗口聚焦和关闭，以及快捷键、自启、清晰度设置。

附件校验值在 SHA256SUMS.txt；安装和隐私说明随下载包提供。
'''
        (output / 'RELEASE_NOTES.md').write_text(notes, encoding='utf-8')
        destination.parent.mkdir(exist_ok=True)
        output.rename(destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--existing', action='store_true', help='打包当前已签名应用，不重新编译；不保证其源码新鲜度')
    parser.add_argument('--zip-only', action='store_true', help='只生成 ZIP，不需要磁盘映像服务')
    parser.add_argument('--channel', choices=['beta', 'stable'], default='beta', help='默认 beta；stable 必须已有公证票据')
    args = parser.parse_args()
    try:
        if not args.existing:
            env = os.environ.copy()
            if args.channel == 'stable':
                env['TASKVIEW_DISTRIBUTION'] = 'developer-id'
            run(['bash', ROOT / 'Scripts/make_app.sh', 'release'], env=env)
        destination = package(ROOT / 'build/TaskView.app', args.channel, args.zip_only, not args.existing)
        print(f'发布附件已生成：{destination}')
        print('请检查 RELEASE_NOTES.md，再把此目录中的附件上传到 GitHub Releases。')
    except (RuntimeError, OSError, plistlib.InvalidFileException, ValueError) as error:
        parser.exit(1, f'打包失败：{error}\n未上传任何内容，也没有替换现有发布目录。\n')


if __name__ == '__main__':
    main()
