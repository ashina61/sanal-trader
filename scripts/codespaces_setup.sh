#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME="$HOME/flutter"
if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
export PATH="$FLUTTER_HOME/bin:$PATH"
if ! grep -Fq '$HOME/flutter/bin' "$HOME/.bashrc" 2>/dev/null; then
  printf '\nexport PATH="$HOME/flutter/bin:$PATH"\n' >> "$HOME/.bashrc"
fi
flutter config --enable-web
flutter create --platforms=web --org com.ashina61 --project-name sanal_trader .
flutter pub get
printf '\nKurulum tamam. Terminalde: flutter run -d web-server --web-hostname 0.0.0.0 --web-port 3000\n'
