#!/usr/bin/env bash
set -euo pipefail

FEATURE_NAME="${1:-}"

if [ -z "$FEATURE_NAME" ]; then
    echo "Usage: $0 <feature-name> [base-ref]"
    exit 1
fi

BASE_REF="${2:-origin/main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_DIR="$ROOT_DIR/patches/$FEATURE_NAME"

DEFAULT_ADD_MESSAGE="clang-mg: add $FEATURE_NAME"
DEFAULT_UPDATE_MESSAGE="clang-mg: update $FEATURE_NAME"

mkdir -p "$PATCH_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: This must be run from inside the LLVM git checkout."
    exit 1
fi

if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
    echo "ERROR: A rebase or git-am operation is currently in progress."
    echo "Finish or abort it before saving feature patches."
    exit 1
fi

if [ -f ".git/MERGE_HEAD" ]; then
    echo "ERROR: A merge is currently in progress."
    echo "Finish or abort it before saving feature patches."
    exit 1
fi

if [ -f ".git/CHERRY_PICK_HEAD" ]; then
    echo "ERROR: A cherry-pick is currently in progress."
    echo "Finish or abort it before saving feature patches."
    exit 1
fi

resolve_base_ref() {
    local requested_ref="$1"
    local current_branch
    local upstream_ref

    current_branch="$(git branch --show-current || true)"

    # If the caller passed the current checked-out branch, using that as a
    # range base is wrong because the branch moves when we commit.
    # Prefer its upstream, like origin/main.
    if [ -n "$current_branch" ] && [ "$requested_ref" = "$current_branch" ]; then
        upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"

        if [ -n "$upstream_ref" ]; then
            echo "$upstream_ref"
            return 0
        fi

        if git rev-parse --verify "origin/$current_branch" >/dev/null 2>&1; then
            echo "origin/$current_branch"
            return 0
        fi
    fi

    echo "$requested_ref"
}

RESOLVED_BASE_REF="$(resolve_base_ref "$BASE_REF")"

if ! git rev-parse --verify "$RESOLVED_BASE_REF" >/dev/null 2>&1; then
    echo "ERROR: Base ref does not exist: $RESOLVED_BASE_REF"
    echo
    echo "Try one of:"
    echo "  git fetch origin --tags"
    echo "  $0 $FEATURE_NAME origin/main"
    echo "  $0 $FEATURE_NAME llvmorg-19.1.0"
    exit 1
fi

existing_patch_count=0
if compgen -G "$PATCH_DIR/*.patch" >/dev/null; then
    existing_patch_count="$(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | wc -l | tr -d ' ')"
fi

new_commit_created=0

echo "=== save feature ==="
echo "Feature:              $FEATURE_NAME"
echo "Requested base ref:   $BASE_REF"
echo "Resolved base ref:    $RESOLVED_BASE_REF"
echo "Patch dir:            $PATCH_DIR"
echo "Existing patch count: $existing_patch_count"
echo

if [ -n "$(git status --porcelain)" ]; then
    echo "Found uncommitted changes."
    echo "Creating a commit before saving patches..."

    git add -A

    if git diff --cached --quiet; then
        echo "No staged changes after git add."
    else
        if [ "$existing_patch_count" -gt 0 ]; then
            commit_message="${COMMIT_MSG:-$DEFAULT_UPDATE_MESSAGE}"
        else
            commit_message="${COMMIT_MSG:-$DEFAULT_ADD_MESSAGE}"
        fi

        git commit -m "$commit_message"
        new_commit_created=1
    fi
else
    echo "No uncommitted changes found."
fi

tmp_patch_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$tmp_patch_dir"
}
trap cleanup EXIT

if [ "$existing_patch_count" -gt 0 ]; then
    patch_count="$existing_patch_count"

    if [ "$new_commit_created" -eq 1 ]; then
        patch_count="$((patch_count + 1))"
    fi

    echo
    echo "Existing patches found."
    echo "Saving the last $patch_count commit(s) as the updated feature patch stack."

    git format-patch "-$patch_count" -o "$tmp_patch_dir"

else
    if [ "$new_commit_created" -eq 1 ]; then
        echo
        echo "No existing patches found."
        echo "Saving the new feature commit as the first patch."

        git format-patch -1 -o "$tmp_patch_dir"
    else
        commits_since_base="$(git rev-list --count "$RESOLVED_BASE_REF"..HEAD)"

        if [ "$commits_since_base" -eq 0 ]; then
            echo
            echo "ERROR: There are no commits to save for this feature."
            echo "Make changes first, then run:"
            echo "  $0 $FEATURE_NAME $RESOLVED_BASE_REF"
            exit 1
        fi

        echo
        echo "No existing patches found."
        echo "No new commit was created, so saving commits from $RESOLVED_BASE_REF..HEAD."

        git format-patch "$RESOLVED_BASE_REF" -o "$tmp_patch_dir"
    fi
fi

rm -f "$PATCH_DIR"/*.patch
cp "$tmp_patch_dir"/*.patch "$PATCH_DIR"/

echo
echo "Saved patches for feature: $FEATURE_NAME"
echo "Patch dir: $PATCH_DIR"
echo
ls -1 "$PATCH_DIR"/*.patch