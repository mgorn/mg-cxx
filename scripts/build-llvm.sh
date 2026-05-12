#!/usr/bin/env bash
set -euo pipefail

LLVM_DIR="${1:-}"
BUILD_DIR="${2:-}"
BUILD_TYPE="${3:-Release}"
JOBS="${4:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

INTERACTIVE=0

shift $(( $# >= 4 ? 4 : $# ))

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interactive)
            INTERACTIVE=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 <llvm-dir> <build-dir> [build-type] [jobs] [--interactive]"
            echo
            echo "Examples:"
            echo "  $0 work/llvm-project work/build"
            echo "  $0 work/llvm-project work/build Release 8"
            echo "  $0 work/llvm-project work/build Release 8 --interactive"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$LLVM_DIR" || -z "$BUILD_DIR" ]]; then
    echo "ERROR: Missing required arguments."
    echo
    echo "Usage:"
    echo "  $0 <llvm-dir> <build-dir> [build-type] [jobs] [--interactive]"
    exit 1
fi

if [[ ! -d "$LLVM_DIR/llvm" ]]; then
    echo "ERROR: Could not find LLVM source directory:"
    echo "  $LLVM_DIR/llvm"
    exit 1
fi

prompt_debug_build() {
    local answer

    if [[ "$INTERACTIVE" -ne 1 ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        echo "Interactive mode requested, but stdin is not a terminal. Using Release build."
        BUILD_TYPE="Release"
        return 0
    fi

    echo
    printf "Build an unoptimized Debug build instead of optimized Release? [y/N]: "
    read -r answer || answer=""

    case "$answer" in
        y|Y|yes|YES|Yes)
            BUILD_TYPE="Debug"
            ;;
        *)
            BUILD_TYPE="Release"
            ;;
    esac
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

prompt_debug_build

if has_cmd ninja; then
    GENERATOR="Ninja"
elif has_cmd ninja-build; then
    GENERATOR="Ninja"
else
    echo "ERROR: Ninja was not found."
    echo "Please install ninja or ninja-build."
    exit 1
fi

echo
echo "Configuring LLVM build..."
echo "LLVM dir:    $LLVM_DIR"
echo "Build dir:   $BUILD_DIR"
echo "Build type:  $BUILD_TYPE"
echo "Jobs:        $JOBS"
echo

cmake -S "$LLVM_DIR/llvm" -B "$BUILD_DIR" \
    -G "$GENERATOR" \
    -DLLVM_ENABLE_PROJECTS="clang" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DLLVM_ENABLE_ASSERTIONS=ON

echo
echo "Building clang..."

cmake --build "$BUILD_DIR" --target clang -- -j "$JOBS"

echo
echo "Build complete."

if [[ -x "$BUILD_DIR/bin/clang-mg" ]]; then
    echo "Built: $BUILD_DIR/bin/clang-mg"
    "$BUILD_DIR/bin/clang-mg" --version || true
elif [[ -x "$BUILD_DIR/bin/clang" ]]; then
    echo "Built: $BUILD_DIR/bin/clang"
    "$BUILD_DIR/bin/clang" --version || true
else
    echo "WARNING: Build finished, but no clang or clang-mg binary was found in:"
    echo "  $BUILD_DIR/bin"
fi