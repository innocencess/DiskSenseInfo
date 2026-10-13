#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc -swift-version 5 -target "$(uname -m)-apple-macosx13.0" Sources/Core.swift Sources/Collector.swift Tests/TestRunner.swift -o build/tests -framework IOKit
build/tests
