#!/bin/bash
set -e

SWIFTUI_MACRO="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins/libSwiftUIMacros.dylib"
TESTING_MACRO="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
XCTEST_FRAMEWORKS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks"
XCTEST_USRLIB="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib"

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
