#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LLVM_URL="${LLVM_URL:-https://github.com/llvm/llvm-project.git}"
LLVM_REF="${LLVM_REF:-main}"

WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
LLVM_DIR="${LLVM_DIR:-$WORK_DIR/llvm-project}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"

BUILD_TYPE="${BUILD_TYPE:-Debug}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

ENABLE_IF_CONSTEXPR_MEMBERS="${ENABLE_IF_CONSTEXPR_MEMBERS:-1}"
ENABLE_CURLINCLUDE="${ENABLE_CURLINCLUDE:-1}"

CLONE_SCRIPT="$ROOT_DIR/scripts/clone-llvm.sh"
UPDATE_SCRIPT="$ROOT_DIR/scripts/update-llvm.sh"
RESET_SCRIPT="$ROOT_DIR/scripts/reset-llvm.sh"
APPLY_PATCHES_SCRIPT="$ROOT_DIR/scripts/apply-patches.sh"
BUILD_LLVM_SCRIPT="$ROOT_DIR/scripts/build-llvm.sh"
SAVE_PATCHES_SCRIPT="$ROOT_DIR/scripts/save-feature-patches.sh"

COMMAND="${1:-bootstrap}"

print_header() {
    echo "=== clang-mg ==="
    echo "Command:       $COMMAND"
    echo "LLVM ref:      $LLVM_REF"
    echo "LLVM dir:      $LLVM_DIR"
    echo "Build dir:     $BUILD_DIR"
    echo "Build type:    $BUILD_TYPE"
    echo "Jobs:          $JOBS"
    echo
}

usage() {
    cat <<EOF
Usage:
  ./build.sh [command]

Commands:
  bootstrap             Clone/update LLVM if needed, apply patches, then build
  clone                 Clone LLVM only
  update                Update LLVM only if the checkout is clean
  reset                 Reset LLVM checkout to LLVM_REF / origin ref
  apply                 Apply clang-mg patches only
  build                 Build current LLVM tree only
  fresh                 Reset LLVM, apply patches, then build
  rebuild               Same as fresh
  save <feature-name>   Save current LLVM commits as patches for a feature
  help                  Show this help menu

Examples:
  ./build.sh
  ./build.sh bootstrap
  ./build.sh build
  ./build.sh fresh
  ./build.sh save curlinclude

Environment variables:
  LLVM_REF=main
  LLVM_URL=https://github.com/llvm/llvm-project.git
  WORK_DIR=$ROOT_DIR/work
  LLVM_DIR=$ROOT_DIR/work/llvm-project
  BUILD_DIR=$ROOT_DIR/work/build
  BUILD_TYPE=Debug
  JOBS=4

Feature toggles:
  ENABLE_IF_CONSTEXPR_MEMBERS=1
  ENABLE_CURLINCLUDE=1
EOF
}

require_llvm_repo() {
    if [ ! -d "$LLVM_DIR/.git" ]; then
        echo "ERROR: LLVM is not cloned yet."
        echo
        echo "Run:"
        echo "  ./build.sh clone"
        echo
        echo "or:"
        echo "  ./build.sh bootstrap"
        exit 1
    fi
}

run_clone() {
    "$CLONE_SCRIPT" \
        "$LLVM_URL" \
        "$LLVM_REF" \
        "$LLVM_DIR"
}

run_update() {
    LLVM_URL="$LLVM_URL" \
    LLVM_REF="$LLVM_REF" \
    WORK_DIR="$WORK_DIR" \
    LLVM_DIR="$LLVM_DIR" \
        "$UPDATE_SCRIPT"
}

run_reset() {
    require_llvm_repo

    cd "$LLVM_DIR"

    "$RESET_SCRIPT" "origin/$LLVM_REF"
}

run_apply_patches() {
    require_llvm_repo

    "$APPLY_PATCHES_SCRIPT" \
        "$ROOT_DIR" \
        "$LLVM_DIR" \
        "$ENABLE_IF_CONSTEXPR_MEMBERS" \
        "$ENABLE_CURLINCLUDE"
}

run_build() {
    require_llvm_repo

    "$BUILD_LLVM_SCRIPT" \
        "$LLVM_DIR" \
        "$BUILD_DIR" \
        "$BUILD_TYPE" \
        "$JOBS"
}

run_save_feature_patches() {
    require_llvm_repo

    local feature_name="${1:-}"

    if [ -z "$feature_name" ]; then
        echo "ERROR: Missing feature name."
        echo
        echo "Usage:"
        echo "  ./build.sh save <feature-name>"
        echo
        echo "Example:"
        echo "  ./build.sh save curlinclude"
        exit 1
    fi

    cd "$LLVM_DIR"

    "$SAVE_PATCHES_SCRIPT" "$feature_name" "$LLVM_REF"
}

print_header

case "$COMMAND" in
    help|-h|--help)
        usage
        ;;

    clone)
        run_clone
        ;;

    update)
        run_update
        ;;

    reset)
        run_reset
        ;;

    apply)
        run_apply_patches
        ;;

    build)
        run_build
        ;;

    bootstrap)
        run_update
        run_apply_patches
        run_build
        ;;

    fresh|rebuild)
        if [ ! -d "$LLVM_DIR/.git" ]; then
            run_clone
        else
            run_reset
        fi

        run_apply_patches
        run_build
        ;;

    save)
        shift
        run_save_feature_patches "${1:-}"
        ;;

    *)
        echo "ERROR: Unknown command: $COMMAND"
        echo
        usage
        exit 1
        ;;
esac

echo
echo "Done."