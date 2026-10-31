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

# O NeyHub (plugin) e as atualizações conferem este certificado fixo (scripts/setup-signing.sh, o mesmo do Aero).
# Sem ele não há fallback ad-hoc.
IDENTITY="Aero Local Signing"
# here-string, não pipe: com pipefail o grep -q saindo cedo pode dar SIGPIPE no security.
IDENTS=$(security find-identity -p codesigning)
if ! grep -q "$IDENTITY" <<<"$IDENTS"; then
  echo "✗ sem a identidade \"$IDENTITY\": rode scripts/setup-signing.sh" >&2
  exit 1
fi

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
# Nome que aparece (Domo) por idioma; o arquivo continua Hub.app.
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Fontes e logos dos apps da TV: os mesmos que o release põe no .neyplugin.
ditto Resources/Bundle "$APP/Contents/Resources"

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
  # Só ao abrir este build para usar: registra o hubmac:// (retorno do login do SmartThings) apontando para ele.
  # Builds de teste (selftest, release) não registram, senão o login iria para eles.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
  pkill -x Hub 2>/dev/null || true
  while pgrep -x Hub >/dev/null; do sleep 0.2; done
  open -n "$APP"
fi
