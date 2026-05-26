#!/usr/bin/env bash
set -euo pipefail

FEATURE_NAME="${1:-}"

if [ -z "$FEATURE_NAME" ] || [ "$FEATURE_NAME" = "-h" ] || [ "$FEATURE_NAME" = "--help" ]; then
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

GIT_DIR="$(git rev-parse --git-dir)"
if [[ "$GIT_DIR" != /* ]]; then
    GIT_DIR="$(pwd)/$GIT_DIR"
fi

if [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ]; then
    echo "ERROR: A rebase or git-am operation is currently in progress."
    echo "Finish or abort it before saving feature patches."
    exit 1
fi

if [ -f "$GIT_DIR/MERGE_HEAD" ]; then
    echo "ERROR: A merge is currently in progress."
    echo "Finish or abort it before saving feature patches."
    exit 1
fi

if [ -f "$GIT_DIR/CHERRY_PICK_HEAD" ]; then
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

get_patch_id_from_file() {
    local patch_path="$1"
    local line

    line="$(git patch-id --stable < "$patch_path" | head -n 1 || true)"
    if [ -z "$line" ]; then
        return 0
    fi

    awk '{print $1}' <<< "$line"
}

get_patch_id_from_commit() {
    local commit="$1"
    local line

    line="$(git show --format=medium --patch --binary "$commit" | git patch-id --stable | head -n 1 || true)"
    if [ -z "$line" ]; then
        return 0
    fi

    awk '{print $1}' <<< "$line"
}

commit_is_selected() {
    local commit="$1"
    local selected

    for selected in "${selected_commits[@]}"; do
        if [ "$selected" = "$commit" ]; then
            return 0
        fi
    done

    return 1
}

add_commit_if_missing() {
    local commit="$1"

    if ! commit_is_selected "$commit"; then
        selected_commits+=("$commit")
    fi
}

commit_summary() {
    local commit="$1"
    local short_hash
    local subject

    short_hash="$(git rev-parse --short "$commit")"
    subject="$(git show -s --format=%s "$commit")"

    echo "$short_hash $subject"
}

write_selected_commit_list() {
    local commit

    for commit in "${selected_commits[@]}"; do
        echo "  $(commit_summary "$commit")"
    done
}

save_selected_commits_as_patches() {
    local output_dir="$1"
    local patch_number=1
    local commit
    local one_commit_dir
    local generated_patches

    for commit in "${selected_commits[@]}"; do
        one_commit_dir="$output_dir/commit-$patch_number"
        mkdir -p "$one_commit_dir"

        git format-patch --zero-commit --start-number "$patch_number" -1 "$commit" -o "$one_commit_dir"

        shopt -s nullglob
        generated_patches=("$one_commit_dir"/*.patch)
        shopt -u nullglob

        if [ "${#generated_patches[@]}" -ne 1 ]; then
            echo "ERROR: Expected exactly one generated patch for commit $commit, but found ${#generated_patches[@]}."
            exit 1
        fi

        mv "${generated_patches[0]}" "$output_dir/"
        rm -rf "$one_commit_dir"

        patch_number="$((patch_number + 1))"
    done
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

existing_patches=()
while IFS= read -r patch_file; do
    existing_patches+=("$patch_file")
done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '*.patch' | sort)

existing_patch_count="${#existing_patches[@]}"
new_commit_created=0

selected_commits=()

status="$(git status --porcelain)"

echo "=== save feature ==="
echo "Feature:              $FEATURE_NAME"
echo "Requested base ref:   $BASE_REF"
echo "Resolved base ref:    $RESOLVED_BASE_REF"
echo "Patch dir:            $PATCH_DIR"
echo "Existing patch count: $existing_patch_count"
echo

if [ -n "$status" ]; then
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
commit_map_file="$tmp_patch_dir/commit-patch-ids.txt"
cleanup() {
    rm -rf "$tmp_patch_dir"
}
trap cleanup EXIT

if [ "$existing_patch_count" -gt 0 ]; then
    echo
    echo "Existing patches found."
    echo "Finding this feature's already-applied commits by patch-id instead of using the last commits on HEAD."

    history_commits=()
    while IFS= read -r commit; do
        history_commits+=("$commit")
    done < <(git rev-list --reverse "$RESOLVED_BASE_REF..HEAD")

    : > "$commit_map_file"

    for commit in "${history_commits[@]}"; do
        patch_id="$(get_patch_id_from_commit "$commit")"

        if [ -z "$patch_id" ]; then
            continue
        fi

        printf '%s %s\n' "$patch_id" "$commit" >> "$commit_map_file"
    done

    missing_patch_matches=()

    for patch in "${existing_patches[@]}"; do
        patch_id="$(get_patch_id_from_file "$patch")"
        candidate=""

        if [ -n "$patch_id" ]; then
            while read -r mapped_patch_id mapped_commit; do
                if [ "$mapped_patch_id" = "$patch_id" ] && ! commit_is_selected "$mapped_commit"; then
                    candidate="$mapped_commit"
                    break
                fi
            done < "$commit_map_file"
        fi

        if [ -z "$candidate" ]; then
            missing_patch_matches+=("$(basename "$patch")")
            continue
        fi

        add_commit_if_missing "$candidate"
    done

    if [ "${#missing_patch_matches[@]}" -gt 0 ]; then
        echo
        echo "ERROR: Could not safely find the applied commit(s) for these existing patch file(s):"
        for patch_name in "${missing_patch_matches[@]}"; do
            echo "  $patch_name"
        done
        echo
        echo "The patch folder was not modified."
        echo "Make sure the feature's current patches are applied to this LLVM checkout before saving."
        exit 1
    fi

    for commit in "${history_commits[@]}"; do
        subject="$(git show -s --format=%s "$commit")"

        if [ "$subject" = "$DEFAULT_ADD_MESSAGE" ] || [ "$subject" = "$DEFAULT_UPDATE_MESSAGE" ]; then
            add_commit_if_missing "$commit"
        fi
    done

    if [ "$new_commit_created" -eq 1 ]; then
        head_commit="$(git rev-parse HEAD)"
        add_commit_if_missing "$head_commit"
    fi

    if [ "${#selected_commits[@]}" -eq 0 ]; then
        echo
        echo "ERROR: No commits were selected for this feature."
        echo "The patch folder was not modified."
        exit 1
    fi

    echo
    echo "Saving these commits as the updated feature patch stack:"
    write_selected_commit_list

    save_selected_commits_as_patches "$tmp_patch_dir"
else
    if [ "$new_commit_created" -eq 1 ]; then
        echo
        echo "No existing patches found."
        echo "Saving the new feature commit as the first patch."

        git format-patch --zero-commit -1 -o "$tmp_patch_dir"
    else
        commits_since_base="$(git rev-list --count "$RESOLVED_BASE_REF..HEAD")"

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
        echo "WARNING: This can include other feature commits if this checkout already has patch stacks applied."

        git format-patch --zero-commit "$RESOLVED_BASE_REF" -o "$tmp_patch_dir"
    fi
fi

shopt -s nullglob
new_patches=("$tmp_patch_dir"/*.patch)
shopt -u nullglob

if [ "${#new_patches[@]}" -eq 0 ]; then
    echo
    echo "ERROR: No patch files were generated."
    exit 1
fi

if [ "$existing_patch_count" -gt 0 ]; then
    backup_dir="$PATCH_DIR.backup.$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"

    for patch in "${existing_patches[@]}"; do
        cp "$patch" "$backup_dir/"
    done

    echo
    echo "Backed up previous patches to:"
    echo "  $backup_dir"
fi

rm -f "$PATCH_DIR"/*.patch
cp "$tmp_patch_dir"/*.patch "$PATCH_DIR"/

echo
echo "Saved patches for feature: $FEATURE_NAME"
echo "Patch dir: $PATCH_DIR"
echo
ls -1 "$PATCH_DIR"/*.patch
