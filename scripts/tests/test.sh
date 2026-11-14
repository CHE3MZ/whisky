#!/bin/bash
#
# test.sh
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Runs the full local test flow: builds every scheme, runs the WhiskyKit unit
# tests and the WhiskyUITests, then prints the XCUITest summary with
# xcresultparser.
#
# Usage: scripts/tests/test.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
RESULT_BUNDLE="$BUILD_DIR/TestResults.xcresult"
cd "$PROJECT_DIR"

bash "$PROJECT_DIR/scripts/build.sh" --full

echo "==> Running WhiskyKit unit tests"
swift test --package-path WhiskyKit --scratch-path "$BUILD_DIR/WhiskyKit"

echo "==> Running WhiskyUITests"
rm -rf "$RESULT_BUNDLE"
xcodebuild \
    -project Whisky.xcodeproj \
    -scheme Whisky \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath build \
    -only-testing:WhiskyUITests \
    -resultBundlePath "$RESULT_BUNDLE" \
    -retry-tests-on-failure \
    -test-iterations 3 \
    test \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

echo "==> Test results"
xcresultparser "$RESULT_BUNDLE"
