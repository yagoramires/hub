#!/bin/zsh
# Compila e empacota o Hub.app em build/ (sem precisar do Xcode).
# Uso: scripts/build.sh [release|debug] [--run] [--dist]
#   --dist  build universal (Apple Silicon + Intel) e zip em dist/ pra publicar no GitHub
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
RUN=0
DIST=0
for arg in "$@"; do
  case $arg in
    debug|release) CONFIG=$arg ;;
    --run) RUN=1 ;;
    --dist) DIST=1 ;;
  esac
done

ARCHS=()
(( DIST )) && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/Hub"

APP=build/Hub.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hub"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# O Keychain libera os tokens só para a mesma assinatura. Com assinatura ad-hoc ela muda a
# cada build e o macOS volta a pedir senha; por isso usamos o certificado local fixo do Aero.
IDENTITY="Aero Local Signing"
if ! security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "⚠ sem certificado local: rode ../aero/scripts/setup-signing.sh, senão o Keychain pede senha a cada build"
  IDENTITY="-"
fi
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "✓ $APP"

if (( DIST )); then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
  mkdir -p dist
  rm -f "dist/Hub-$VERSION.zip"
  ditto -c -k --norsrc --keepParent "$APP" "dist/Hub-$VERSION.zip"
  echo "✓ dist/Hub-$VERSION.zip"
fi

if (( RUN )); then
  pkill -x Hub 2>/dev/null || true
  while pgrep -x Hub >/dev/null; do sleep 0.2; done
  open -n "$APP"
fi
