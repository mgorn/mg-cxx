#!/usr/bin/env bash
set -euo pipefail

LLVM_URL="$1"
LLVM_REF="$2"
LLVM_DIR="$3"

if [ ! -d "$LLVM_DIR/.git" ]; then
    echo "Cloning LLVM..."
    mkdir -p "$(dirname "$LLVM_DIR")"
    git clone "$LLVM_URL" "$LLVM_DIR"
else
    echo "LLVM checkout already exists."
fi

cd "$LLVM_DIR"

echo "Fetching LLVM updates..."
git fetch origin --tags

echo "Checking out LLVM ref: $LLVM_REF"
git checkout "$LLVM_REF"

echo "Resetting working tree..."
git reset --hard

echo "Creating clang-mg build branch..."
git checkout -B clang-mg-build