#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LLVM_DIR="${2:-$ROOT_DIR/work/llvm-project}"

PATCH_ROOT="$ROOT_DIR/patches"
APPLY_FEATURE_SCRIPT="$ROOT_DIR/scripts/apply-feature.sh"

echo "=== apply all clang-mg patches ==="
echo "Root dir:   $ROOT_DIR"
echo "LLVM dir:   $LLVM_DIR"
echo "Patch root: $PATCH_ROOT"
echo

if [ ! -d "$LLVM_DIR/.git" ]; then
    echo "ERROR: LLVM repo is not cloned:"
    echo "$LLVM_DIR"
    exit 1
fi

if [ ! -d "$PATCH_ROOT" ]; then
    echo "ERROR: Patch directory does not exist:"
    echo "$PATCH_ROOT"
    exit 1
fi

if [ ! -x "$APPLY_FEATURE_SCRIPT" ]; then
    echo "ERROR: apply-feature script not found or not executable:"
    echo "$APPLY_FEATURE_SCRIPT"
    echo
    echo "Try:"
    echo "  chmod +x \"$APPLY_FEATURE_SCRIPT\""
    exit 1
fi

cd "$LLVM_DIR"

if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: LLVM has uncommitted changes."
    echo
    echo "Save, commit, or reset your changes before applying patches."
    echo
    echo "Useful commands:"
    echo "  git status"
    echo "  git diff"
    echo "  git add ."
    echo "  git commit -m \"clang-mg: describe current work\""
    echo
    echo "Apply cancelled."
    exit 1
fi

apply_loose_patches() {
    if ! compgen -G "$PATCH_ROOT/*.patch" > /dev/null; then
        echo "No loose top-level patches found."
        return 0
    fi

    echo
    echo "Applying loose top-level patches from:"
    echo "$PATCH_ROOT"

    git am --3way "$PATCH_ROOT"/*.patch
}

apply_feature_dirs() {
    local feature_dir
    local feature_name
    local found_feature=0

    echo
    echo "Applying feature patch directories..."

    while IFS= read -r feature_dir; do
        feature_name="$(basename "$feature_dir")"

        if ! compgen -G "$feature_dir/*.patch" > /dev/null; then
            echo "Skipping feature with no .patch files: $feature_name"
            continue
        fi

        found_feature=1

        echo
        echo "Applying feature: $feature_name"

        LLVM_DIR="$LLVM_DIR" \
            "$APPLY_FEATURE_SCRIPT" "$feature_name"

    done < <(find "$PATCH_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)

    if [ "$found_feature" -eq 0 ]; then
        echo "No feature patch directories found."
    fi
}

apply_loose_patches
apply_feature_dirs

echo
echo "All available clang-mg patches applied."