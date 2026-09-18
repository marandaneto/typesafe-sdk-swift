#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
: "${DEVELOPER_DIR:?Set DEVELOPER_DIR to the selected Xcode Contents/Developer directory}"

build_platform() {
    local name="$1" triple="$2" platform="$3"
    local sdk="$DEVELOPER_DIR/Platforms/$platform.platform/Developer/SDKs/$platform.sdk"
    test -d "$sdk"
    echo "Building TypeSafe for $name ($triple)"
    swift build --target TypeSafe --configuration release \
        --scratch-path ".build/ci-platforms/$name" \
        --triple "$triple" --sdk "$sdk" \
        -Xswiftc -warnings-as-errors
}

build_platform macos arm64-apple-macosx13.0 MacOSX
build_platform macos-intel x86_64-apple-macosx13.0 MacOSX
build_platform ios arm64-apple-ios16.0 iPhoneOS
build_platform ios-simulator-arm64 arm64-apple-ios16.0-simulator iPhoneSimulator
build_platform ios-simulator-intel x86_64-apple-ios16.0-simulator iPhoneSimulator
build_platform catalyst arm64-apple-ios16.0-macabi MacOSX
build_platform tvos arm64-apple-tvos16.0 AppleTVOS
build_platform watchos arm64_32-apple-watchos9.0 WatchOS
build_platform visionos arm64-apple-xros1.0 XROS
