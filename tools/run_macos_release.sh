#!/bin/bash
# Project-local Release runner; closing the app ends this command as well.
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

flutter_bin="${FLUTTER_BIN:-flutter}"
host_arch="$(uname -m)"
case "$host_arch" in
  arm64|x86_64) ;;
  *) echo "Unsupported macOS architecture: $host_arch" >&2; exit 1 ;;
esac

# Generate Flutter settings and install/update pods without Flutter's generic
# 'Any Mac' build destination. Forward build options, e.g. --dart-define=K=V.
"$flutter_bin" build macos --release --config-only "$@"
xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination "platform=macOS,arch=$host_arch" \
  -derivedDataPath build/macos \
  -quiet \
  "ARCHS=$host_arch" \
  ONLY_ACTIVE_ARCH=YES \
  build

# exec replaces the runner with the app; there is no Flutter daemon left waiting
# for a VM service disconnect event that Release mode never produces.
exec "$project_root/build/macos/Build/Products/Release/terminal_use_app.app/Contents/MacOS/terminal_use_app"
