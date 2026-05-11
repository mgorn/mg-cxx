#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

LLVM_URL="${LLVM_URL:-https://github.com/llvm/llvm-project.git}"
LLVM_REF="${LLVM_REF:-main}"

WORK_DIR="${WORK_DIR:-$ROOT_DIR/work}"
LLVM_DIR="${LLVM_DIR:-$WORK_DIR/llvm-project}"

CLONE_SCRIPT="$SCRIPT_DIR/clone-llvm.sh"

echo "=== update LLVM ==="
echo "LLVM ref:  $LLVM_REF"
echo "LLVM dir:  $LLVM_DIR"
echo

if [ ! -d "$LLVM_DIR/.git" ]; then
    echo "LLVM is not cloned yet."

    if [ ! -x "$CLONE_SCRIPT" ]; then
        echo "ERROR: clone script not found or not executable:"
        echo "$CLONE_SCRIPT"
        echo
        echo "Try:"
        echo "chmod +x \"$CLONE_SCRIPT\""
        exit 1
    fi

    echo "Calling clone-llvm.sh..."
    "$CLONE_SCRIPT" "$LLVM_URL" "$LLVM_REF" "$LLVM_DIR"
    exit 0
fi

cd "$LLVM_DIR"

echo "Checking LLVM working tree..."

# Check for unfinished git operations first.
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
    echo "ERROR: A rebase is currently in progress."
    echo "Finish or abort it before updating LLVM."
    exit 1
fi

if [ -f ".git/MERGE_HEAD" ]; then
    echo "ERROR: A merge is currently in progress."
    echo "Finish or abort it before updating LLVM."
    exit 1
fi

if [ -d ".git/rebase-apply" ] || [ -f ".git/CHERRY_PICK_HEAD" ]; then
    echo "ERROR: A cherry-pick or patch application is currently in progress."
    echo "Finish or abort it before updating LLVM."
    exit 1
fi

# Check for uncommitted changes.
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: LLVM has uncommitted changes."
    echo
    echo "You may be working on a feature patch right now."
    echo "Save your feature patches before updating LLVM."
    echo
    echo "Useful commands:"
    echo "  git status"
    echo "  git diff"
    echo "  git add ."
    echo "  git commit -m \"clang-mg: describe feature\""
    echo "  ../clang-mg/scripts/save-feature-patches.sh <feature-name> $LLVM_REF"
    echo
    echo "Update cancelled."
    exit 1
fi

echo "LLVM working tree is clean."
echo

echo "Fetching latest LLVM changes..."
git fetch origin --tags

CURRENT_BRANCH="$(git branch --show-current || true)"

if [ -z "$CURRENT_BRANCH" ]; then
    echo "LLVM checkout is detached."
    echo "Checking out requested ref: $LLVM_REF"
    git checkout "$LLVM_REF"

    CURRENT_BRANCH="$(git branch --show-current || true)"

    if [ -z "$CURRENT_BRANCH" ]; then
        echo "Still detached after checkout."
        echo "Fetch complete, but there is no branch to pull."
        echo "LLVM is at:"
        git --no-pager log --oneline -1
        exit 0
    fi
fi

echo "Current branch: $CURRENT_BRANCH"

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

if [ -n "$UPSTREAM" ]; then
    echo "Pulling from upstream: $UPSTREAM"
    git pull --ff-only
else
    echo "No upstream is configured for branch: $CURRENT_BRANCH"

    if git show-ref --verify --quiet "refs/remotes/origin/$CURRENT_BRANCH"; then
        echo "Found matching remote branch: origin/$CURRENT_BRANCH"
        echo "Pulling with fast-forward only..."
        git pull --ff-only origin "$CURRENT_BRANCH"
    else
        echo "No matching remote branch found."
        echo "Fetch completed, but nothing was pulled."
        echo
        echo "You can manually update with something like:"
        echo "  git checkout main"
        echo "  git pull --ff-only origin main"
        exit 0
    fi
fi

echo
echo "LLVM updated successfully."
git --no-pager log --oneline -1