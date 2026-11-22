#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter create --platforms=android --org com.example --project-name sanal_trader .
flutter pub get
flutter run
