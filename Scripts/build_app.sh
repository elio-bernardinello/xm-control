#!/bin/bash
# Build a local app without touching an installed copy. Only Apple developer tools
# are required. A failed build/signature leaves the last packaged app intact.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
case "$CONFIG" in
    release|debug) ;;
    *) echo "Usage: $0 [release|debug]" >&2; exit 2 ;;
esac
APP_NAME="XM Control"
APP_DIR=".build/${APP_NAME}.app"
# A stable identity keeps the Bluetooth (TCC) grant across rebuilds: ad-hoc
# signatures change on every build, so macOS asks again each time. Prefer the
# Apple Development certificate in the keychain; fall back to the local XMDev
# identity, then to ad hoc.
if [ -n "${XM_SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$XM_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q '"Apple Development:'; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)"
elif security find-identity -p codesigning 2>/dev/null | grep -Fq '"XMDev"'; then
    SIGN_IDENTITY="XMDev"
else
    SIGN_IDENTITY=""
fi

swift build -c "$CONFIG" --product XM6Control
BUILD_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
STAGING="$(mktemp -d .build/xm-package.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
STAGED_APP="$STAGING/${APP_NAME}.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

# Vector icon, no Sony photo required. make_icon.swift always renders
# .build/AppIcon.iconset + Sources/.../AppIcon.icns; convert the iconset
# into the staged bundle.
swift Scripts/make_icon.swift
iconutil -c icns ".build/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/XMIcon.icns"
cp "$BUILD_DIR/XM6Control" "$STAGED_APP/Contents/MacOS/XM6Control"
cp Sources/XM6Control/Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
for lang in fr en; do
  mkdir -p "$STAGED_APP/Contents/Resources/$lang.lproj"
  cp "Sources/XM6Control/Resources/$lang.lproj/InfoPlist.strings" "$STAGED_APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
done
for photo in xm4 xm5 xm6; do
  if [ -f "Sources/XM6Control/Resources/$photo.png" ]; then
    cp "Sources/XM6Control/Resources/$photo.png" "$STAGED_APP/Contents/Resources/"
  fi
done
cp LICENSE Sources/XM6Control/Resources/ImageCredits.txt "$STAGED_APP/Contents/Resources/"
if [ -f Sources/XM6Control/Resources/headphones.png ]; then
    cp Sources/XM6Control/Resources/headphones.png "$STAGED_APP/Contents/Resources/"
fi
plutil -lint "$STAGED_APP/Contents/Info.plist"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signature : ${SIGN_IDENTITY}"
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGED_APP"
else
    echo "Signature ad hoc locale (une nouvelle autorisation Bluetooth peut être nécessaire)."
    codesign --force --sign - "$STAGED_APP"
fi
codesign --verify --strict --verbose=1 "$STAGED_APP"

# Replace only our previous build product, after successful assembly and signing.
rm -rf "$APP_DIR"
mv "$STAGED_APP" "$APP_DIR"
echo "Application prête : $APP_DIR"
echo "Aucune application installée n’a été remplacée ou lancée."
