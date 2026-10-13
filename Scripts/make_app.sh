#!/bin/bash
# 使用 swiftc 编译并组装应用；必须通过证书签名后才发布构建产物。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
case "$CONFIG" in
    release|debug) ;;
    *) echo "Usage: $0 [release|debug]" >&2; exit 2 ;;
esac
IDENTITY="${TASKVIEW_SIGNING_IDENTITY:-TaskView Local Signer}"
DISTRIBUTION="${TASKVIEW_DISTRIBUTION:-local}"
case "$DISTRIBUTION" in
    local|developer-id) ;;
    *) echo "TASKVIEW_DISTRIBUTION must be local or developer-id." >&2; exit 2 ;;
esac
if [[ -z "$IDENTITY" || "$IDENTITY" == "-" ]]; then
    echo "A certificate signing identity is required; ad-hoc signing is disabled." >&2
    exit 1
fi

SDK="$(xcrun --show-sdk-path)"
mkdir -p build/bin
STAGING="$(mktemp -d "$PWD/build/signing-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
OUT="$STAGING/TaskView"

FLAGS=(-sdk "$SDK" -target arm64-apple-macos14.0 -module-name TaskView -swift-version 5
       -module-cache-path "$PWD/build/ModuleCache")

if [[ "$CONFIG" == "debug" ]]; then
    FLAGS+=(-Onone -g -D DEBUG)
else
    FLAGS+=(-O)
fi

swiftc "${FLAGS[@]}" Sources/TaskView/*.swift -o "$OUT"

APP="$STAGING/TaskView.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$OUT" "$APP/Contents/MacOS/TaskView"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${TASKVIEW_VERSION:-}" ]]; then
    [[ "$TASKVIEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "版本号应为三个数字段，例如 1.0.0。" >&2; exit 2; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TASKVIEW_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${TASKVIEW_BUILD_NUMBER:-}" ]]; then
    [[ "$TASKVIEW_BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "构建号应为整数。" >&2; exit 2; }
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $TASKVIEW_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
SIGN_FLAGS=(--force --sign "$IDENTITY")
if [[ "$DISTRIBUTION" == developer-id ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

if ! codesign "${SIGN_FLAGS[@]}" "$APP"; then
    echo "Certificate signing failed. Existing build/TaskView.app was preserved." >&2
    echo "Install the local signing identity with: bash Scripts/install_local_signer.sh" >&2
    exit 1
fi
codesign --verify --strict "$APP"
DETAILS="$(codesign -dvv "$APP" 2>&1)"
if [[ "$DISTRIBUTION" == developer-id && "$DETAILS" != *"Authority=Developer ID Application:"* ]]; then
    echo "正式分发需要 Developer ID Application 身份，拒绝发布此构建。" >&2
    exit 1
fi
if [[ "$DETAILS" == *"Signature=adhoc"* || "$DETAILS" != *"Authority="* ]]; then
    echo "A certificate signature could not be verified; refusing to publish the build." >&2
    exit 1
fi

# 签名和验证成功后才替换应用，失败时保留旧版本。
if [[ -d build/TaskView.app ]]; then
    mv build/TaskView.app "$STAGING/PreviousTaskView.app"
fi
if ! mv "$APP" build/TaskView.app; then
    if [[ -d "$STAGING/PreviousTaskView.app" ]]; then
        mv "$STAGING/PreviousTaskView.app" build/TaskView.app
    fi
    exit 1
fi
cp build/TaskView.app/Contents/MacOS/TaskView build/bin/TaskView
echo "Signed with certificate: $IDENTITY"

echo "Built: build/TaskView.app ($CONFIG)"
