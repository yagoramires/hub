#!/bin/zsh
# Empacota uma release local: dist/<Nome>-<v>.{dmg,zip,neyplugin} + notas em build/notes-<v>.md.
# Copie para <app>/scripts/release.sh e ajuste NAME / PLUGIN_PRODUCT (vazio = app sem plugin).
# Só empacota. Publicar exige --publish E NEYHUB_CONFIRM_PUBLISH=yes (senão só mostra o que faria).
# Uso: scripts/release.sh [--dry-run] [--publish]
set -euo pipefail
setopt nullglob
cd "$(dirname "$0")/.."

NAME="Hub"
PLUGIN_PRODUCT="HubPlugin"
# No próprio neyhub usa o checkout atual; num app, ../neyhub (ou NEYHUB_PATH).
if [[ -x ./scripts/changelog-section.sh && -f ./Sources/NeyHub/main.swift ]]; then NEYHUB_PATH=.; fi
NEYHUB_PATH="${NEYHUB_PATH:-../neyhub}"
[[ -x "$NEYHUB_PATH/scripts/changelog-section.sh" ]] || { echo "✗ neyhub não encontrado em \"$NEYHUB_PATH\" (falta scripts/changelog-section.sh): defina NEYHUB_PATH" >&2; exit 1; }

PUBLISH=0
for arg in "$@"; do
  case $arg in
    --dry-run) ;;  # já é o padrão; mantido por compatibilidade
    --publish) PUBLISH=1 ;;
    *) echo "uso: $0 [--dry-run] [--publish]" >&2; exit 2 ;;
  esac
done

IDENTITY="Aero Local Signing"
# here-string, não pipe: com pipefail, o grep -q saindo cedo pode dar SIGPIPE no security e um falso "sem identidade".
IDENTS=$(security find-identity -p codesigning)
grep -q "$IDENTITY" <<<"$IDENTS" || { echo "✗ sem a identidade \"$IDENTITY\"" >&2; exit 1; }
# Requisito fixo que o NeyHub (plugins) e o Updater (apps) conferem; lido do NeyKit para o hash não ter duas cópias.
SIG="$NEYHUB_PATH/Sources/NeyKit/PluginSignature.swift"
LEAF=$(grep -o 'certificate leaf = H"[0-9a-f]\{40\}"' "$SIG" || true)
[[ -n "$LEAF" ]] || { echo "✗ requisito fixo não encontrado em $SIG" >&2; exit 1; }
VALIDATOR="$NEYHUB_PATH/build/NeyHub.app/Contents/MacOS/NeyHub"
if [[ -n "$PLUGIN_PRODUCT" && ! -x "$VALIDATOR" ]]; then
  echo "✗ validador não encontrado: $VALIDATOR (rode scripts/build.sh no neyhub ou defina NEYHUB_PATH)" >&2
  exit 1
fi

V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
NOTES="build/notes-$V.md"
mkdir -p build dist
"$NEYHUB_PATH/scripts/changelog-section.sh" "$V" CHANGELOG.md > "$NOTES" || { rm -f "$NOTES"; exit 1; }
rm -f "dist/$NAME-$V".*

# App universal assinado + zip (o build.sh --dist faz os dois)
scripts/build.sh release --dist
APP="build/$NAME.app"
ASSETS=("dist/$NAME-$V.zip")
# Resources/Bundle/ (fontes, logos...) vai para o .app e, mais abaixo, para o plugin. O build.sh já assinou e zipou: reassina e refaz o zip.
BUNDLE=Resources/Bundle
if [[ -d $BUNDLE ]]; then
  ditto "$BUNDLE" "$APP/Contents/Resources"
  codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
  rm -f "dist/$NAME-$V.zip"; ditto -c -k --norsrc --keepParent "$APP" "dist/$NAME-$V.zip"
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" Resources/Info.plist)
codesign -v --strict -R "=identifier \"$BUNDLE_ID\" and $LEAF" "$APP" || { echo "✗ $APP não passa no requisito fixo: o Updater recusaria" >&2; exit 1; }

# dmg: .app + atalho para /Applications
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/$NAME-$V.dmg" >/dev/null
ASSETS=("dist/$NAME-$V.dmg" "${ASSETS[@]}")

# Plugin: pasta + manifest + dylib assinada (+ ícone) -> zip com extensão .neyplugin
if [[ -n "$PLUGIN_PRODUCT" ]]; then
  swift build -c release --arch arm64 --arch x86_64 --product "$PLUGIN_PRODUCT"
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/lib$PLUGIN_PRODUCT.dylib"
  PLG="build/$NAME.neyplugin"
  rm -rf "$PLG"; mkdir -p "$PLG"
  python3 - Resources/plugin.json "$V" "$PLG/manifest.json" <<'PY'
import json, sys
src, version, out = sys.argv[1:]
m = json.load(open(src))
m.update(version=version, contract=1)
json.dump(m, open(out, "w"), indent=2, ensure_ascii=False)
PY
  "$VALIDATOR" --validate-manifest "$PLG/manifest.json"
  BINARY=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary"])' "$PLG/manifest.json")
  cp "$BIN" "$PLG/$BINARY"
  [[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$PLG/icon.icns"
  # Resources/ do .neyplugin fica fora da assinatura (só o dylib é assinado), como o manifest.json.
  if [[ -d $BUNDLE ]]; then mkdir -p "$PLG/Resources"; ditto "$BUNDLE" "$PLG/Resources"; fi
  codesign --force --sign "$IDENTITY" --timestamp=none "$PLG/$BINARY"
  codesign -v -R "=$LEAF" "$PLG/$BINARY" || { echo "✗ $PLG/$BINARY não passa no requisito fixo: o NeyHub recusaria" >&2; exit 1; }
  ditto -c -k --norsrc --keepParent "$PLG" "dist/$NAME-$V.neyplugin"
  ASSETS+=("dist/$NAME-$V.neyplugin")
fi

# Exatamente 1 .zip (o do app); o .neyplugin não conta
ZIPS=("dist/$NAME-$V"*.zip); N=${#ZIPS}
(( N == 1 )) || { echo "✗ esperado 1 .zip em dist/ para $V, achei $N" >&2; exit 1; }
for a in "${ASSETS[@]}"; do echo "✓ $a"; done
echo "✓ notas: $NOTES"

if (( PUBLISH )) && [[ "${NEYHUB_CONFIRM_PUBLISH:-}" == yes ]]; then
  gh release create "v$V" "${ASSETS[@]}" --verify-tag --title "$NAME $V" --notes-file "$NOTES"
else
  echo "(só empacotado) publicaria v$V com: ${ASSETS[*]}"
  echo "  para publicar: --publish e NEYHUB_CONFIRM_PUBLISH=yes"
fi
