#!/usr/bin/env bash
set -euo pipefail

BASE_REF="${1:-origin/main}"

echo "Resetting LLVM checkout to: $BASE_REF"

git am --abort 2>/dev/null || true
git rebase --abort 2>/dev/null || true
git merge --abort 2>/dev/null || true

git checkout main
git fetch origin
git reset --hard "$BASE_REF"
git clean -fd

echo "LLVM checkout reset."