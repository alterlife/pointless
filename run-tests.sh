#!/bin/bash
set -e

echo "🧪 Building test target..."

# Build the PointlessCore library first
swift build --target PointlessCore

# Compile tests manually with XCTest
swiftc -module-name PointlessTests \
    -I .build/debug \
    -L .build/debug \
    -lPointlessCore \
    -F /Library/Developer/CommandLineTools/usr/lib/swift/macosx \
    -framework XCTest \
    -Xlinker -rpath -Xlinker .build/debug \
    Tests/PointlessTests/*.swift \
    -o .build/PointlessTests

echo "✅ Tests compiled successfully"
echo "🏃 Running tests..."

# Run the tests
.build/PointlessTests

echo "✅ All tests passed!"
