#!/bin/bash
# 基础回归默认运行；--ui 另外运行需要窗口服务器的控件与网格测试。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 \
    -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
    Sources/TaskView/OverlayController.swift Sources/TaskView/OverlayWindow.swift Sources/TaskView/AppSettings.swift \
    Sources/TaskView/WindowQuery.swift Sources/TaskView/ThumbnailLoader.swift \
    Sources/TaskView/WindowCloseService.swift Sources/TaskView/WindowMatcher.swift \
    Tests/OverlayLifecycleTests.swift -o build/tests/OverlayLifecycleTests
build/tests/OverlayLifecycleTests
swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 \
    -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
    Sources/TaskView/AppSettings.swift Sources/TaskView/LoginItemController.swift \
    Sources/TaskView/Permissions.swift \
    Sources/TaskView/WindowMatcher.swift Tests/TestSupport.swift Tests/SettingsTests.swift -o build/tests/SettingsTests
build/tests/SettingsTests
swiftc -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
    Sources/TaskView/DebugLog.swift Tests/DebugLogTests.swift -o build/tests/DebugLogTests
build/tests/DebugLogTests
python3 Tests/ProfileIdleTests.py
python3 Tests/ReleasePackageTests.py
swiftc -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
    Sources/TaskView/WindowQuery.swift Tests/WindowQueryTests.swift -o build/tests/WindowQueryTests
build/tests/WindowQueryTests
swiftc -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
    Sources/TaskView/ThumbnailLoader.swift Tests/ThumbnailLoaderTests.swift -o build/tests/ThumbnailLoaderTests
build/tests/ThumbnailLoaderTests
swiftc -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
    Sources/TaskView/WindowCloseService.swift Sources/TaskView/WindowMatcher.swift \
    Tests/WindowCloseTests.swift -o build/tests/WindowCloseTests
build/tests/WindowCloseTests
if [[ "${1:-}" == "--ui" ]]; then
    swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 \
        -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
        Sources/TaskView/AppSettings.swift Sources/TaskView/AppBuildInfo.swift Sources/TaskView/LoginItemController.swift \
        Sources/TaskView/Permissions.swift Sources/TaskView/SettingsWindowController.swift \
        Sources/TaskView/GlobalHotKey.swift \
        Tests/TestSupport.swift Tests/SettingsUITests.swift -o build/tests/SettingsUITests
    build/tests/SettingsUITests
    swiftc -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14.0 \
        -swift-version 5 -module-cache-path "$PWD/build/ModuleCache" \
        Sources/TaskView/OverlayContentView.swift Sources/TaskView/WindowCellView.swift \
        Sources/TaskView/OverlayWindow.swift \
        Sources/TaskView/WindowQuery.swift Sources/TaskView/AppSettings.swift \
        Tests/WindowGridTests.swift -o build/tests/WindowGridTests
    build/tests/WindowGridTests
fi
