#!/bin/bash
set -e

SWIFTUI_MACRO="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
TESTING_MACRO="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
XCTEST_FRAMEWORKS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
XCTEST_USRLIB="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib"
XCTEST_RUNNER="/Applications/Xcode.app/Contents/Developer/usr/bin/xctest"

# --filter <pattern> applies to both passes; XCTest only takes exact class or class/method names.
FILTER=""
ARGS=("$@")
for ((i = 0; i < ${#ARGS[@]}; i++)); do
  if [ "${ARGS[$i]}" = "--filter" ]; then
    FILTER="${ARGS[$((i + 1))]}"
  fi
done

swift test \
  -Xswiftc -load-plugin-library -Xswiftc "$SWIFTUI_MACRO" \
  -Xswiftc -load-plugin-library -Xswiftc "$TESTING_MACRO" \
  -Xswiftc -F -Xswiftc "$XCTEST_FRAMEWORKS" \
  -Xswiftc -I -Xswiftc "$XCTEST_USRLIB" \
  -Xlinker -F -Xlinker "$XCTEST_FRAMEWORKS" \
  -Xlinker -framework -Xlinker XCTest \
  -Xlinker -L -Xlinker "$XCTEST_USRLIB" \
  -Xlinker -rpath -Xlinker "$XCTEST_FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$XCTEST_USRLIB" \
  "$@"

# Pass 2: XCTest cases. With the Command Line Tools toolchain, `swift test` only runs Swift Testing
# and silently skips XCTestCase subclasses, so run the same test bundle with Xcode's xctest runner.
# Pick the bundle whose binary was just built: older toolchains left stale bundles elsewhere in .build.
BUNDLE=""
for candidate in .build/out/Products/Debug/*.xctest .build/*/debug/*PackageTests.xctest; do
  bin="$candidate/Contents/MacOS/$(basename "$candidate" .xctest)"
  if [ -f "$bin" ] && { [ -z "$BUNDLE" ] || [ "$bin" -nt "$BUNDLE_BIN" ]; }; then
    BUNDLE="$candidate"
    BUNDLE_BIN="$bin"
  fi
done
if [ ! -x "$XCTEST_RUNNER" ] || [ -z "$BUNDLE" ]; then
  echo "⚠️  XCTest cases skipped: Xcode's xctest runner or the test bundle was not found."
  exit 0
fi

XCTEST_ARGS=()
if [ -n "$FILTER" ]; then
  if [[ "$FILTER" =~ ^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$ ]] && grep -rqs "class ${FILTER%%/*}: XCTestCase" Tests; then
    XCTEST_ARGS=(-XCTest "$FILTER")
  else
    exit 0
  fi
fi

echo "🧪 Running XCTest cases..."
DYLD_FRAMEWORK_PATH="$XCTEST_FRAMEWORKS" DYLD_LIBRARY_PATH="$XCTEST_USRLIB" \
  "$XCTEST_RUNNER" "${XCTEST_ARGS[@]}" "$BUNDLE"
