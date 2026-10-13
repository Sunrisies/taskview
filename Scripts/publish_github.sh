#!/bin/bash
# 在维护者正常终端发布已经打包的 Beta；不重新签名，不强推，不覆盖发布。
set -euo pipefail
cd "$(dirname "$0")/.."
repo='Sunrisies/taskview'
remote='git@github.com:Sunrisies/taskview.git'
check_only=false
source_only=false
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --check-only) check_only=true ;;
        --source-only) source_only=true ;;
        *) echo "未知选项：$1" >&2; exit 1 ;;
    esac
    shift
done
if [[ "$#" -gt 1 ]]; then
    echo '用法：bash Scripts/publish_github.sh [--check-only] [--source-only] [发布目录]' >&2
    exit 1
fi
release_dir="${1:-dist/TaskView-1.0.0-beta.1-arm64}"

# 限制提交范围，核对下载附件的完整性，拒绝包内凭据和不一致的元数据。
tag=$(python3 - "$release_dir" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import sys
import zipfile

root = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((root / 'release-manifest.json').read_text())
assert manifest['channel'] == 'beta', '当前发布脚本仅支持 Beta 预发布'
version, build = manifest['version'], manifest['build']
assert re.fullmatch(r'\d+\.\d+\.\d+', version) and re.fullmatch(r'\d+', build)
assert (root / 'RELEASE_NOTES.md').is_file()
checks = {}
for line in (root / 'SHA256SUMS.txt').read_text().splitlines():
    digest, name = line.split(maxsplit=1)
    assert name not in checks, '校验文件中有重复附件'
    checks[name] = digest
assert checks == manifest['artifacts_sha256'], '校验文件与发布元数据不一致'
assert any(name.endswith('.zip') for name in checks), '缺少 ZIP 下载附件'
for name, expected in checks.items():
    assert pathlib.Path(name).name == name and name.endswith(('.zip', '.dmg'))
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == expected, name + ' 校验失败'
    if name.endswith('.zip'):
        with zipfile.ZipFile(root / name) as archive:
            assert archive.testzip() is None, 'ZIP 数据损坏'
            assert any(n.endswith('/TaskView.app/Contents/MacOS/TaskView') for n in archive.namelist())
            plists = [n for n in archive.namelist() if n.endswith('/TaskView.app/Contents/Info.plist')]
            assert len(plists) == 1, 'ZIP 必须只包含一个 TaskView 应用'
            info = plistlib.loads(archive.read(plists[0]))
            assert info['CFBundleIdentifier'] == 'com.zhuzhongqian.taskview', '应用标识不正确'
            assert info['CFBundleShortVersionString'] == version and info['CFBundleVersion'] == build, '应用与发布版本不一致'
            for entry in archive.namelist():
                path = pathlib.PurePosixPath(entry)
                assert '..' not in path.parts and not path.is_absolute(), 'ZIP 路径不安全'
                assert path.suffix.lower() not in {'.key', '.p12', '.pfx', '.p8', '.pem'}, 'ZIP 含私密签名材料'
                assert not any(p.startswith('.env') or p == 'signing' for p in path.parts), 'ZIP 含凭据目录'
files = subprocess.check_output(['git', 'ls-files', '-z']).decode().split('\0')
# 未跟踪但即将添加的维护文件也必须检查，不能只检查旧的暂存区。
files += subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '-z', '--',
    '.gitignore', 'README.md', 'LICENSE', 'Sources', 'Scripts', 'Tests', 'Docs', '.github']).decode().split('\0')
for name in filter(None, files):
    path = pathlib.PurePosixPath(name)
    assert name in {'.gitignore', 'README.md', 'LICENSE'} or path.parts[0] in {'Sources', 'Scripts', 'Tests', 'Docs', '.github'}, '意外的 Git 文件：' + name
    assert path.suffix.lower() not in {'.key', '.p12', '.pfx', '.p8', '.pem', '.crt', '.log'}, 'Git 含私密或生成文件：' + name
    assert not any(p.startswith('.env') or p in {'signing', '__pycache__'} for p in path.parts), 'Git 含凭据或缓存：' + name
    local_path = pathlib.Path(name)
    if local_path.is_file():
        content = local_path.read_bytes()
        assert not re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|(?:ghp_|github_pat_)[A-Za-z0-9_]{30,}', content), '文件含疑似私钥或 GitHub Token：' + name
print('v' + version + '-beta.' + build)
PY
)
echo "附件和 Git 文件范围检查通过：$tag"
if "$check_only"; then
    echo '仅检查完成；未提交、推送或发布。签名会在实际发布前验证。'
    exit 0
fi

# 先确认账号和远程，认证失败时不创建提交。
if ! "$source_only"; then
    gh auth status
fi
branch=$(git branch --show-current)
[[ "$branch" == 'main' ]] || { echo '请先切换到 main 分支。' >&2; exit 1; }
existing_remote=$(git remote get-url origin 2>/dev/null || true)
[[ -z "$existing_remote" || "$existing_remote" == "$remote" ]] || { echo 'origin 地址不同，停止发布。' >&2; exit 1; }
refs=$(git ls-remote "$remote")
if [[ -n "$refs" ]]; then
    git rev-parse --verify HEAD >/dev/null 2>&1 || { echo '远程已有历史而本地尚无提交，请先合并远程历史。' >&2; exit 1; }
    git fetch "$remote" main
    git merge-base --is-ancestor FETCH_HEAD HEAD || { echo '远程 main 尚未合并，停止发布。' >&2; exit 1; }
fi
[[ -z "$(git ls-remote "$remote" "refs/tags/$tag" "refs/tags/$tag^{}")" ]] || { echo '远程标签已存在，请检查现有发布。' >&2; exit 1; }
if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo '本地标签已存在，请检查之前发布是否完成。' >&2
    exit 1
fi
if ! "$source_only"; then
    releases=$(gh release list --repo "$repo" --limit 1000 --json tagName)
    python3 -c 'import json,sys; assert all(r["tagName"] != sys.argv[1] for r in json.load(sys.stdin)), "同名发布已存在"' "$tag" <<< "$releases"
fi

# 使用系统工具解包后验证证书签名；临时内容始终清理。
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/taskview-publish.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT
zip_path=$(python3 - "$release_dir" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
names = json.loads((root / 'release-manifest.json').read_text())['artifacts_sha256']
print(root / next(n for n in names if n.endswith('.zip')))
PY
)
ditto -x -k "$zip_path" "$temp_dir"
app_path=$(find "$temp_dir" -type d -name 'TaskView.app' -print -quit)
[[ -n "$app_path" ]] || { echo 'ZIP 内未找到应用。' >&2; exit 1; }
codesign --verify --strict "$app_path"
signature=$(codesign -dvv "$app_path" 2>&1)
[[ "$signature" == *'Authority='* && "$signature" != *'Signature=adhoc'* ]] || { echo '下载包未使用证书签名。' >&2; exit 1; }

# 只添加维护文件；忽略的缓存、签名材料及下载附件留在原目录。
[[ -n "$existing_remote" ]] || git remote add origin "$remote"
git add -- .gitignore README.md Sources Scripts Tests Docs
for optional in LICENSE .github; do
    [[ ! -e "$optional" ]] || git add -- "$optional"
done
git diff --cached --check
if ! git diff --cached --quiet; then
    git commit -m "Release TaskView $tag"
fi
git rev-parse --verify HEAD >/dev/null
git push -u origin main
git tag -a "$tag" -m "TaskView $tag"
git push origin "refs/tags/$tag"
if "$source_only"; then
    echo "源码和标签已推送；尚未创建下载发布。"
    echo "打开 https://github.com/$repo/releases/new ，选择标签 $tag 并勾选 Pre-release。"
    echo "说明使用 $release_dir/RELEASE_NOTES.md；上传 ZIP、可选 DMG、SHA256SUMS.txt 和 release-manifest.json。"
    exit 0
fi
assets=("$zip_path" "$release_dir/SHA256SUMS.txt" "$release_dir/release-manifest.json")
for dmg in "$release_dir"/*.dmg; do
    [[ ! -f "$dmg" ]] || assets+=("$dmg")
done
gh release create "$tag" "${assets[@]}" --repo "$repo" --verify-tag \
    --title "TaskView ${tag#v}" --notes-file "$release_dir/RELEASE_NOTES.md" --prerelease
echo "发布完成：https://github.com/$repo/releases/tag/$tag"
