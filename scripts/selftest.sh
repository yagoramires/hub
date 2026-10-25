#!/bin/zsh
# Roda o --selftest de dentro do .app (bundle id local.hub) e falha se houver classe duplicada
# entre módulos ("is implemented in both"). O stderr só aparece quando algo falha.
set -euo pipefail
cd "$(dirname "$0")/.."

ERR=$(mktemp)
trap 'rm -f "$ERR"' EXIT
scripts/build.sh debug >"$ERR" 2>&1 || { cat "$ERR" >&2; exit 1; }
rc=0
build/Hub.app/Contents/MacOS/Hub --selftest 2>"$ERR" || rc=$?
if grep -q "is implemented in both" "$ERR"; then
  echo "✗ classe duplicada entre módulos:" >&2; cat "$ERR" >&2; exit 1
fi
if (( rc != 0 )); then
  echo "✗ selftest falhou (exit $rc):" >&2; cat "$ERR" >&2; exit $rc
fi
