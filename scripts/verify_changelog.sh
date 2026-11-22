#!/usr/bin/env bash
set -euo pipefail

# Require release notes on every subsequent non-changelog commit.
# CI fetches two commits so HEAD^ is available on push and pull_request.
if ! git rev-parse --verify 'HEAD^' >/dev/null 2>&1; then
  echo "First commit; no previous tree to compare."
  exit 0
fi
changed="$(git diff --name-only HEAD^ HEAD)"
if [[ -z "$changed" ]]; then
  exit 0
fi

if printf '%s\n' "$changed" | grep -qvE '^(CHANGELOG\.md|assets/changelog\.json)$'; then
  if ! printf '%s\n' "$changed" | grep -qx 'CHANGELOG.md'; then
    echo "::error::Every application change must update CHANGELOG.md"
    exit 1
  fi
  if ! printf '%s\n' "$changed" | grep -qx 'assets/changelog.json'; then
    echo "::error::Every application change must update assets/changelog.json"
    exit 1
  fi
fi

python3 - <<'PY'
import json, pathlib
releases = json.loads(pathlib.Path('assets/changelog.json').read_text(encoding='utf-8'))['releases']
assert releases, 'At least one release note is required'
assert all(r.get('version') and r.get('date') and r.get('details') for r in releases)
assert len({r['version'] for r in releases}) == len(releases), 'Duplicate release version'
assert all(isinstance(item, str) and item.strip() for r in releases for item in r['details'])
print('Release history exists and contains valid entries.')
PY
