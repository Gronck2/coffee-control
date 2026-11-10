#!/bin/bash
# Builds CoffeeControl.app with its Control Center extension, using swiftc only.
#
#   ./build.sh            build into ./build/CoffeeControl.app
#   ./build.sh install    build, copy to ~/Applications, register the extension
#   ./build.sh clean      remove ./build
#
# Needs the macOS 26 SDK: Xcode 26, or Command Line Tools for Xcode 26.x.
# Environment:
#   CODESIGN_IDENTITY   signing identity, default "-" (ad-hoc). Set to an
#                       "Apple Development: ..." identity if ad-hoc signing is
#                       not enough for Control Center.
#   INSTALL_DIR         default ~/Applications
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"

APP_NAME="CoffeeControl"
EXT_NAME="CoffeeControlExtension"
APP_ID="local.coffeecontrol.CoffeeControl"
EXT_ID="$APP_ID.Control"
VERSION="0.1.0"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
DEPLOYMENT="26.0"
ARCH="$(uname -m)"
TRIPLE="$ARCH-apple-macos$DEPLOYMENT"
IDENTITY="${CODESIGN_IDENTITY:--}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"

BUILD="$ROOT/build"
OBJ="$BUILD/obj"
APP="$BUILD/$APP_NAME.app"
EXT="$APP/Contents/PlugIns/$EXT_NAME.appex"

say() { printf '\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning: %s\033[0m\n' "$*" >&2; }
die() { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

check_sdk() {
  SDK="$(xcrun --sdk macosx --show-sdk-path)"
  SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
  if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
    die "macOS SDK $SDK_VERSION at $SDK is too old: ControlWidgetToggle needs the macOS 26 SDK.
Install Xcode 26 or Command Line Tools for Xcode 26.x."
  fi
  say "SDK $SDK_VERSION ($SDK)"
}

# compile <module> <output binary> <objdir> <extra flags...> -- <sources...>
compile() {
  local module="$1" out="$2" objdir="$3"
  shift 3
  local flags=()
  while [[ "$1" != "--" ]]; do flags+=("$1"); shift; done
  shift
  mkdir -p "$objdir" "$(dirname "$out")"
  # Const values feed the App Intents metadata processor (see gen_metadata).
  xcrun swiftc \
    -sdk "$SDK" -target "$TRIPLE" \
    -module-name "$module" -parse-as-library \
    -swift-version 6 -O -whole-module-optimization \
    -emit-const-values-path "$objdir/$module.swiftconstvalues" \
    -Xfrontend -const-gather-protocols-file \
    -Xfrontend "$ROOT/Support/appintents-protocols.json" \
    "${flags[@]}" \
    -o "$out" "$@"
}

# Writes Contents/Resources/Metadata.appintents. Without it the system does not
# know ToggleCoffeeIntent, and the toggle shows up but does nothing.
# gen_metadata <module> <bundle id> <binary> <resources dir> <objdir> <sources...>
gen_metadata() {
  local module="$1" bundle_id="$2" binary="$3" resources="$4" objdir="$5"
  shift 5
  local processor
  if ! processor="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    # Command Line Tools only: write the index ourselves from the const values.
    say "$module: appintentsmetadataprocessor not found, using Support/gen_appintents_metadata.py"
    python3 -I "$ROOT/Support/gen_appintents_metadata.py" "$resources" "$objdir/$module.swiftconstvalues"
    [[ -f "$resources/Metadata.appintents/extract.actionsdata" ]] \
      || die "$module: Metadata.appintents/extract.actionsdata was not produced"
    return 0
  fi
  local toolchain xcode_build
  toolchain="$(cd "$(dirname "$processor")/../.." && pwd)"
  xcode_build="$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}')"
  printf '%s\n' "$@" > "$objdir/sources.txt"
  printf '%s\n' "$objdir/$module.swiftconstvalues" > "$objdir/constvalues.txt"
  : > "$objdir/metadata-deps.txt"
  : > "$objdir/static-metadata.txt"
  mkdir -p "$resources"
  "$processor" \
    --toolchain-dir "$toolchain" \
    --module-name "$module" \
    --sdk-root "$SDK" \
    --xcode-version "${xcode_build:-unknown}" \
    --platform-family macOS \
    --deployment-target "$DEPLOYMENT" \
    --bundle-identifier "$bundle_id" \
    --output "$resources" \
    --target-triple "$TRIPLE" \
    --binary-file "$binary" \
    --dependency-file "$objdir/$module.appintents.d" \
    --stringsdata-file "$objdir/ExtractedAppShortcutsMetadata.stringsdata" \
    --source-file-list "$objdir/sources.txt" \
    --metadata-file-list "$objdir/metadata-deps.txt" \
    --static-metadata-file-list "$objdir/static-metadata.txt" \
    --swift-const-vals-list "$objdir/constvalues.txt" \
    --compile-time-extraction \
    --deployment-aware-processing \
    --no-app-shortcuts-localization
  [[ -f "$resources/Metadata.appintents/extract.actionsdata" ]] \
    || die "$module: Metadata.appintents/extract.actionsdata was not produced"
}

plist() {
  sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" "$1" > "$2"
  plutil -lint -s "$2"
}

build() {
  check_sdk
  rm -rf "$APP" "$OBJ"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" \
           "$EXT/Contents/MacOS" "$EXT/Contents/Resources"

  local shared=("$ROOT"/Sources/Shared/*.swift)
  local app_sources=("${shared[@]}" "$ROOT"/Sources/App/*.swift)
  local ext_sources=("${shared[@]}" "$ROOT"/Sources/Widget/*.swift)

  say "compile $APP_NAME"
  compile "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME" "$OBJ/app" \
    -D COFFEE_APP -- "${app_sources[@]}"

  say "compile $EXT_NAME"
  # Xcode links every app extension with entry point _NSExtensionMain. Linked at
  # the @main WidgetBundle instead, the extension registers but never loads.
  compile "$EXT_NAME" "$EXT/Contents/MacOS/$EXT_NAME" "$OBJ/ext" \
    -application-extension -Xlinker -e -Xlinker _NSExtensionMain -- "${ext_sources[@]}"

  say "App Intents metadata"
  gen_metadata "$APP_NAME" "$APP_ID" "$APP/Contents/MacOS/$APP_NAME" \
    "$APP/Contents/Resources" "$OBJ/app" "${app_sources[@]}"
  gen_metadata "$EXT_NAME" "$EXT_ID" "$EXT/Contents/MacOS/$EXT_NAME" \
    "$EXT/Contents/Resources" "$OBJ/ext" "${ext_sources[@]}"

  plist "$ROOT/Support/App-Info.plist" "$APP/Contents/Info.plist"
  plist "$ROOT/Support/Control-Info.plist" "$EXT/Contents/Info.plist"
  printf 'APPL????' > "$APP/Contents/PkgInfo"

  say "codesign (identity: $IDENTITY)"
  # Inside out: the extension first, then the app that contains it.
  codesign --force --sign "$IDENTITY" --timestamp=none \
    --entitlements "$ROOT/Support/Control.entitlements" "$EXT"
  codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
  codesign --verify --deep --strict "$APP"

  check_extension_entry
  say "built $APP"
}

# A binary that starts at _NSExtensionMain refuses to run standalone with
# "An XPC Service cannot be run directly." One linked at @main traps instead.
check_extension_entry() {
  local out
  out="$(perl -e 'alarm 5; exec @ARGV' "$EXT/Contents/MacOS/$EXT_NAME" 2>&1 || true)"
  if [[ "$out" == *"cannot be run directly"* ]]; then
    say "extension entry point: _NSExtensionMain"
  else
    warn "extension did not answer like an XPC service; output: ${out:0:300}"
  fi
}

install_app() {
  local dest="$INSTALL_DIR/$APP_NAME.app"
  mkdir -p "$INSTALL_DIR"
  if pgrep -x "$APP_NAME" >/dev/null; then
    say "quit running $APP_NAME"
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || pkill -x "$APP_NAME" || true
    sleep 1
  fi
  # chronod keeps the extension process alive between taps; a stale one keeps
  # running the old binary after reinstall.
  pkill -x "$EXT_NAME" 2>/dev/null || true
  say "install to $dest"
  rm -rf "$dest"
  ditto "$APP" "$dest"
  local lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  # Only the installed copy should be known to LaunchServices and PlugInKit;
  # a second registered copy in ./build makes chronod flip between the two.
  "$lsregister" -u "$APP" >/dev/null 2>&1 || true
  pluginkit -r "$EXT" >/dev/null 2>&1 || true
  "$lsregister" -f -R "$dest"
  pluginkit -a "$dest/Contents/PlugIns/$EXT_NAME.appex"
  say "registered extensions:"
  pluginkit -m -v -i "$EXT_ID" || warn "pluginkit does not list $EXT_ID yet"
  cat <<EOF

Next:
  1. Control Center -> Edit Controls -> search "Coffee" -> drag the toggle in.
     If it is missing, open the widget gallery once (right-click the desktop ->
     Edit Widgets...) to make macOS refresh the list.
  2. Test without the control:  open coffeecontrol://on   |  open coffeecontrol://off
     Check:                      pmset -g assertions | grep -i coffee
EOF
}

case "${1:-build}" in
  build) build ;;
  install) build; install_app ;;
  clean) rm -rf "$BUILD" ;;
  *) die "usage: $0 [build|install|clean]" ;;
esac
