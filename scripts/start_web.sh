#!/usr/bin/env bash
set -euo pipefail

# Codespaces / Flutter web: listen on all interfaces so port 3000 can be forwarded.
export PATH="${HOME}/flutter/bin:${PATH}"
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter bulunamadi. Codespaces ilk kurulumunun tamamlanmasini bekle veya bash scripts/codespaces_setup.sh calistir."
  exit 1
fi

echo "SanalTrader web preview on port 3000 (local mode, no Firebase)."
echo "Codespaces > Ports > 3000 > Open in Browser"
echo "For hot restart press R; for hot reload press r (when supported)."
exec flutter run -d web-server --web-hostname 0.0.0.0 --web-port 3000
