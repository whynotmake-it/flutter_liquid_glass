#!/bin/bash

# Liquid Glass Renderer Performance Benchmark Script
# This script runs integration tests to measure the performance of liquid glass rendering

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    exit 1
fi

# Get current directory (should be the example directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="$(dirname "$SCRIPT_DIR")"

print_info "Running Liquid Glass Renderer Performance Benchmarks"
print_info "Example directory: $EXAMPLE_DIR"

# Change to example directory
cd "$EXAMPLE_DIR"

# Get the first available macOS device
MACOS_DEVICE=$(flutter devices | grep "macos" | head -n 1 | sed 's/.*• \([^ ]*\) .*/\1/')

if [ -z "$MACOS_DEVICE" ]; then
    print_error "No macOS device found. Please ensure macOS desktop support is enabled."
    print_info "Run: flutter config --enable-macos-desktop"
    exit 1
fi

print_info "Using macOS device: $MACOS_DEVICE"

# Check if integration test exists
if [ ! -f "integration_test/benchmark_test.dart" ]; then
    print_error "Integration test file not found: integration_test/benchmark_test.dart"
    exit 1
fi

# Check if test driver exists
if [ ! -f "test_driver/perf_driver.dart" ]; then
    print_error "Test driver file not found: test_driver/perf_driver.dart"
    exit 1
fi

# Run the benchmark
print_info "Starting performance benchmark tests on $MACOS_DEVICE..."
print_warning "This may take several minutes..."

if flutter drive \
    --driver=test_driver/perf_driver.dart \
    --target=integration_test/benchmark_test.dart \
    --profile \
    -d "$MACOS_DEVICE"; then
    
    print_success "Benchmark tests completed successfully!"
    
    # Check for generated files
    if [ -d "build" ]; then
        RESULT_FILES=$(find build -name "*.timeline*.json" 2>/dev/null | wc -l)
        if [ "$RESULT_FILES" -gt 0 ]; then
            print_success "Found $RESULT_FILES performance result files in build/ directory"
            echo ""
            print_info "Performance result files:"
            find build -name "*.timeline*.json" | sort | while read -r file; do
                echo "  - $file"
            done
            echo ""
            print_info "Analysis instructions:"
            echo "  1. Summary files (*_summary.timeline_summary.json) contain performance metrics"
            echo "  2. Timeline files (*.timeline.json) can be opened in Chrome at chrome://tracing"
            echo "  3. Look for frame build times, missed frames, and rasterizer performance"
        else
            print_warning "No performance result files found in build/ directory"
        fi
    else
        print_warning "Build directory not found"
    fi
else
    print_error "Benchmark tests failed!"
    exit 1
fi

print_success "Benchmark script completed!"