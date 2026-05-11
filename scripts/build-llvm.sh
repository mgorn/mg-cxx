#!/usr/bin/env bash
set -euo pipefail

LLVM_DIR="$1"
BUILD_DIR="$2"
BUILD_TYPE="$3"
JOBS="$4"

echo
echo "Configuring LLVM build..."

cmake -S "$LLVM_DIR/llvm" -B "$BUILD_DIR" \
  -G Ninja \
  -DLLVM_ENABLE_PROJECTS="clang" \
  -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
  -DLLVM_ENABLE_ASSERTIONS=ON

echo
echo "Building clang..."

cmake --build "$BUILD_DIR" --target clang -- -j "$JOBS"