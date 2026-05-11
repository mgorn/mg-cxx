#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$1"
LLVM_DIR="$2"
ENABLE_IF_CONSTEXPR_MEMBERS="$3"
ENABLE_CURLINCLUDE="$4"

cd "$LLVM_DIR"

apply_patch_dir() {
    local patch_dir="$1"
    local name="$2"

    if [ ! -d "$patch_dir" ]; then
        echo "Skipping missing patch directory: $patch_dir"
        return
    fi

    if ! compgen -G "$patch_dir/*.patch" > /dev/null; then
        echo "No patches found for: $name"
        return
    fi

    echo
    echo "Applying patch group: $name"
    git am "$patch_dir"/*.patch
}

echo "Applying clang-mg patches..."

apply_patch_dir "$ROOT_DIR/patches/core" "core"

if [ "$ENABLE_IF_CONSTEXPR_MEMBERS" = "1" ]; then
    apply_patch_dir "$ROOT_DIR/patches/if-constexpr-members" "if constexpr members"
fi

if [ "$ENABLE_CURLINCLUDE" = "1" ]; then
    apply_patch_dir "$ROOT_DIR/patches/curlinclude" "curlinclude"
fi

echo
echo "All enabled patches applied."