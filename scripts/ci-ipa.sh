#!/usr/bin/env bash
# Construye las dos IPA sin firmar (Release, dispositivo):
#   build/ipa/Trajet-full.ipa  app + extension de widgets/Live Activity
#   build/ipa/Trajet-lite.ipa  solo la app
# La full lleva una firma ad hoc («-») SOLO para que los entitlements (el App
# Group) viajen dentro de la IPA y el firmador (Signulous...) los vea. No es
# una firma de verdad: el firmador la sustituye por la suya.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ipa

compilar() {   # esquema
  local scheme=$1
  if ! xcodebuild build -project Trajet.xcodeproj -scheme "$scheme" \
      -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
      -derivedDataPath "build/dev-$scheme" \
      CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
      ONLY_ACTIVE_ARCH=NO > "build/ipa-$scheme.log" 2>&1; then
    grep -E "error:" "build/ipa-$scheme.log" | sort -u | head -80
    exit 1
  fi
}

empaquetar() {   # app nombre
  local app=$1 out=$2 tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/Payload"
  cp -R "$app" "$tmp/Payload/"
  (cd "$tmp" && zip -qry "$OLDPWD/build/ipa/$out" Payload)
  rm -rf "$tmp"
  ls -lh "build/ipa/$out"
}

echo "==> full"
compilar Trajet
full="build/dev-Trajet/Build/Products/Release-iphoneos/Trajet.app"
test -d "$full/PlugIns/TrajetWidgets.appex" || { echo "falta la extension en la IPA full"; exit 1; }
codesign --force --sign - --entitlements TrajetWidgets/TrajetWidgets.entitlements \
  "$full/PlugIns/TrajetWidgets.appex"
codesign --force --sign - --entitlements Trajet/App/Trajet.entitlements "$full"
codesign -d --entitlements - "$full" 2>/dev/null | grep -q "group.com.ismaeloul.trajet" \
  || { echo "la IPA full no lleva el App Group"; exit 1; }
empaquetar "$full" Trajet-full.ipa

echo "==> lite"
compilar TrajetLite
lite="build/dev-TrajetLite/Build/Products/Release-iphoneos/Trajet.app"
test ! -d "$lite/PlugIns" || { echo "la IPA lite no debe llevar extensiones"; exit 1; }
/usr/libexec/PlistBuddy -c "Print :NSSupportsLiveActivities" "$lite/Info.plist" | grep -q false \
  || { echo "la lite no debe anunciar Live Activities"; exit 1; }
empaquetar "$lite" Trajet-lite.ipa

for ipa in build/ipa/*.ipa; do
  echo "--- $ipa"; unzip -l "$ipa" | grep -E "Info.plist$|appex/$" | head -5
done
