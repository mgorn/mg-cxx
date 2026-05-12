#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LLVM_URL="${LLVM_URL:-https://github.com/llvm/llvm-project.git}"
LLVM_REF="${LLVM_REF:-main}"

WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
LLVM_DIR="${LLVM_DIR:-$WORK_DIR/llvm-project}"
BUILD_DIR="${BUILD_DIR:-$WORK_DIR/build}"

BUILD_TYPE="${BUILD_TYPE:-Release}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

CLONE_SCRIPT="$ROOT_DIR/scripts/clone-llvm.sh"
UPDATE_SCRIPT="$ROOT_DIR/scripts/update-llvm.sh"
RESET_SCRIPT="$ROOT_DIR/scripts/reset-llvm.sh"
APPLY_PATCHES_SCRIPT="$ROOT_DIR/scripts/apply-patches.sh"
APPLY_FEATURE_SCRIPT="$ROOT_DIR/scripts/apply-feature.sh"
BUILD_LLVM_SCRIPT="$ROOT_DIR/scripts/build-llvm.sh"
SAVE_FEATURE_SCRIPT="$ROOT_DIR/scripts/save-feature.sh"
INSTALL_SCRIPT="$ROOT_DIR/scripts/install-clang-mg.sh"

COMMAND="${1:-bootstrap}"

INTERACTIVE="${INTERACTIVE:-0}"

if [[ "${2:-}" == "--interactive" || "${1:-}" == "--interactive" ]]; then
    INTERACTIVE=1
fi

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
  bootstrap                  Clone/update LLVM if needed, apply all patches, then build
  install                    Clone/update LLVM, reset clean, apply all patches, build, then add clang-mg to PATH
  clone                      Clone LLVM only
  update                     Update LLVM only if the checkout is clean
  reset                      Reset LLVM checkout to LLVM_REF / origin ref
  apply                      Apply all clang-mg patches
  apply <feature-name...>    Apply one or more specific feature patch stacks
  build                      Build current LLVM tree only
  fresh                      Reset LLVM, apply all patches, then build
  rebuild                    Same as fresh
  save <feature-name>        Save current LLVM changes as patches for a feature
  help                       Show this help menu

Examples:
  ./build.sh
  ./build.sh bootstrap
  ./build.sh install
  ./build.sh apply
  ./build.sh apply change-bin-name
  ./build.sh apply change-bin-name curlinclude
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

resolve_reset_ref() {
    require_llvm_repo

    cd "$LLVM_DIR"

    git fetch origin --tags

    if git show-ref --verify --quiet "refs/remotes/origin/$LLVM_REF"; then
        echo "origin/$LLVM_REF"
    else
        echo "$LLVM_REF"
    fi
}

run_reset() {
    require_llvm_repo

    local reset_ref
    reset_ref="$(resolve_reset_ref)"

    cd "$LLVM_DIR"

    "$RESET_SCRIPT" "$reset_ref"
}

run_apply_patches() {
    require_llvm_repo

    "$APPLY_PATCHES_SCRIPT" \
        "$ROOT_DIR" \
        "$LLVM_DIR"
}

run_apply_features() {
    require_llvm_repo

    if [ "$#" -eq 0 ]; then
        run_apply_patches
        return 0
    fi

    local feature_name

    for feature_name in "$@"; do
        LLVM_DIR="$LLVM_DIR" \
            "$APPLY_FEATURE_SCRIPT" "$feature_name"
    done
}

run_build() {
    require_llvm_repo

    if [[ "$INTERACTIVE" -eq 1 ]]; then
        "$BUILD_LLVM_SCRIPT" \
            "$LLVM_DIR" \
            "$BUILD_DIR" \
            "$BUILD_TYPE" \
            "$JOBS" \
            --interactive
    else
        "$BUILD_LLVM_SCRIPT" \
            "$LLVM_DIR" \
            "$BUILD_DIR" \
            "$BUILD_TYPE" \
            "$JOBS"
    fi
}

run_install_path() {
    require_llvm_repo

    BUILD_DIR="$BUILD_DIR" \
        "$INSTALL_SCRIPT" "$BUILD_DIR"
}

run_save_feature() {
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

    "$SAVE_FEATURE_SCRIPT" "$feature_name" "$LLVM_REF"
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
        shift
        run_apply_features "$@"
        ;;

    build)
        run_build
        ;;

    bootstrap)
        run_update
        run_apply_patches
        run_build
        ;;

    install)
        run_update

        # Make sure we are applying patches onto a clean LLVM base.
        # This prevents accidentally applying the same patch stack twice.
        run_reset

        run_apply_patches
        run_build
        run_install_path
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
        run_save_feature "${1:-}"
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