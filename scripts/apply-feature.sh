#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
LLVM_DIR="${LLVM_DIR:-$WORK_DIR/llvm-project}"

FEATURE_NAME="${1:-}"

usage() {
    cat <<EOF
Usage:
  scripts/apply-feature.sh <feature-name>

Examples:
  scripts/apply-feature.sh core
  scripts/apply-feature.sh curlinclude
  scripts/apply-feature.sh if-constexpr-members

Environment variables:
  LLVM_DIR=$LLVM_DIR
  WORK_DIR=$WORK_DIR
EOF
}

list_features() {
    echo "Available features:"

    if [ ! -d "$ROOT_DIR/patches" ]; then
        echo "  No patches directory found."
        return
    fi

    find "$ROOT_DIR/patches" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -exec basename {} \; \
        | sort \
        | sed 's/^/  /'
}

if [ "$FEATURE_NAME" = "-h" ] || [ "$FEATURE_NAME" = "--help" ] || [ -z "$FEATURE_NAME" ]; then
    usage
    echo
    list_features
    exit 0
fi

if [ "$FEATURE_NAME" = "list" ] || [ "$FEATURE_NAME" = "--list" ]; then
    list_features
    exit 0
fi

PATCH_DIR="$ROOT_DIR/patches/$FEATURE_NAME"

echo "=== apply feature ==="
echo "Feature:   $FEATURE_NAME"
echo "Patch dir: $PATCH_DIR"
echo "LLVM dir:  $LLVM_DIR"
echo

if [ ! -d "$LLVM_DIR/.git" ]; then
    echo "ERROR: LLVM repo is not cloned:"
    echo "$LLVM_DIR"
    echo
    echo "Run:"
    echo "  ./build.sh clone"
    echo
    echo "or:"
    echo "  ./build.sh bootstrap"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "ERROR: Feature patch directory does not exist:"
    echo "$PATCH_DIR"
    echo
    list_features
    exit 1
fi

if ! compgen -G "$PATCH_DIR/*.patch" > /dev/null; then
    echo "ERROR: No .patch files found in:"
    echo "$PATCH_DIR"
    exit 1
fi

cd "$LLVM_DIR"

if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
    echo "ERROR: A rebase is currently in progress."
    echo "Finish or abort it before applying feature patches."
    exit 1
fi

if [ -f ".git/MERGE_HEAD" ]; then
    echo "ERROR: A merge is currently in progress."
    echo "Finish or abort it before applying feature patches."
    exit 1
fi

if [ -f ".git/CHERRY_PICK_HEAD" ]; then
    echo "ERROR: A cherry-pick is currently in progress."
    echo "Finish or abort it before applying feature patches."
    exit 1
fi

if [ -d ".git/rebase-apply" ]; then
    echo "ERROR: A patch application may already be in progress."
    echo "Run one of these inside LLVM first:"
    echo "  git am --continue"
    echo "  git am --abort"
    exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: LLVM has uncommitted changes."
    echo
    echo "Save or commit your current work before applying feature patches."
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

echo "Applying feature patches..."
git am --3way "$PATCH_DIR"/*.patch

echo
echo "Applied feature successfully: $FEATURE_NAME"
git --no-pager log --oneline -5