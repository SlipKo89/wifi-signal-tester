#!/usr/bin/env bash
# Generates the native Android/iOS/macOS scaffolding around the existing lib/ code
# and fetches dependencies. Run once after installing Flutter.
#
# Safe to re-run: `flutter create` regenerates the platform folders without
# touching your Dart sources in lib/.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. See README (Requirements) first." >&2
  exit 1
fi

echo "==> Generating platform folders (android/, ios/, macos/)…"
flutter create \
  --org com.slipko \
  --project-name wifi_apk \
  --platforms=android,ios,macos \
  .

echo "==> Fetching packages…"
flutter pub get

echo
echo "Done. Next:"
echo "  1) Add Wi-Fi/location permissions — see docs/android-setup.md"
echo "  2) flutter run           # on a connected device"
echo "  3) flutter build apk     # release APK in build/app/outputs/flutter-apk/"
echo "  4) flutter build macos   # release app in build/macos/Build/Products/Release/"
