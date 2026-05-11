#!/usr/bin/env bash
set -euo pipefail

FEATURE_NAME="${1:-}"

if [ -z "$FEATURE_NAME" ]; then
    echo "Usage: $0 <feature-name> [base-ref]"
    exit 1
fi

BASE_REF="${2:-main}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_DIR="$ROOT_DIR/patches/$FEATURE_NAME"

mkdir -p "$PATCH_DIR"
rm -f "$PATCH_DIR"/*.patch

git format-patch "$BASE_REF" -o "$PATCH_DIR"

echo "Saved patches for feature: $FEATURE_NAME"
echo "Patch dir: $PATCH_DIR"