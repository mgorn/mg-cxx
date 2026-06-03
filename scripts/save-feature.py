#!/usr/bin/env python3
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from clang_mg_common import git, git_dir, git_in_progress_paths, git_output, root_from_script, timestamp


def usage(script_name: str) -> None:
    print(f"Usage: {script_name} <feature-name> [base-ref]")


def git_lines(args: list[str]) -> list[str]:
    text = git_output(args)
    return [line.strip() for line in text.splitlines() if line.strip()]


def resolve_base_ref(requested_ref: str) -> str:
    current_branch = git_output(["branch", "--show-current"], check=False)
    if current_branch and requested_ref == current_branch:
        upstream = git_output(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], check=False)
        if upstream:
            return upstream
        cp = git(["rev-parse", "--verify", f"origin/{current_branch}"], check=False, quiet=True)
        if cp.returncode == 0:
            return f"origin/{current_branch}"
    return requested_ref


def patch_id_from_file(patch_path: Path) -> str:
    with patch_path.open("rb") as f:
        cp = subprocess.run(["git", "patch-id", "--stable"], stdin=f, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=False)
    if cp.returncode != 0 or not cp.stdout:
        return ""
    return cp.stdout.decode(errors="replace").strip().split()[0] if cp.stdout.decode(errors="replace").strip() else ""


def patch_id_from_commit(commit: str) -> str:
    show = subprocess.run(["git", "show", "--format=medium", "--patch", "--binary", commit], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if show.returncode != 0:
        return ""
    pid = subprocess.run(["git", "patch-id", "--stable"], input=show.stdout, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if pid.returncode != 0 or not pid.stdout:
        return ""
    text = pid.stdout.decode(errors="replace").strip()
    return text.split()[0] if text else ""


def commit_summary(commit: str) -> str:
    short_hash = git_output(["rev-parse", "--short", commit])
    subject = git_output(["show", "-s", "--format=%s", commit])
    return f"{short_hash} {subject}"


def add_commit_if_missing(selected: list[str], selected_set: set[str], commit: str) -> None:
    if commit not in selected_set:
        selected.append(commit)
        selected_set.add(commit)


def write_selected_commit_list(selected: list[str]) -> None:
    for commit in selected:
        print(f"  {commit_summary(commit)}")


def save_selected_commits_as_patches(selected: list[str], output_dir: Path) -> None:
    patch_number = 1
    for commit in selected:
        one_commit_dir = output_dir / f"commit-{patch_number}"
        one_commit_dir.mkdir(parents=True, exist_ok=True)
        git(["format-patch", "--zero-commit", "--start-number", str(patch_number), "-1", commit, "-o", str(one_commit_dir)])
        generated = sorted(one_commit_dir.glob("*.patch"))
        if len(generated) != 1:
            print(f"ERROR: Expected exactly one generated patch for commit {commit}, but found {len(generated)}.")
            raise SystemExit(1)
        shutil.move(str(generated[0]), str(output_dir / generated[0].name))
        shutil.rmtree(one_commit_dir, ignore_errors=True)
        patch_number += 1


def main(argv: list[str]) -> int:
    script_name = Path(__file__).name
    feature_name = argv[0] if argv else ""
    if not feature_name or feature_name in {"-h", "--help"}:
        usage(script_name)
        return 1
    base_ref = argv[1] if len(argv) >= 2 else "origin/main"

    root_dir = root_from_script(__file__)
    patch_dir = root_dir / "patches" / feature_name
    default_add_message = f"clang-mg: add {feature_name}"
    default_update_message = f"clang-mg: update {feature_name}"
    patch_dir.mkdir(parents=True, exist_ok=True)

    cp = git(["rev-parse", "--is-inside-work-tree"], check=False, quiet=True)
    if cp.returncode != 0:
        print("ERROR: This must be run from inside the LLVM git checkout.")
        return 1

    paths = git_in_progress_paths(Path.cwd())
    if paths.get("rebase_merge", Path()).is_dir() or paths.get("rebase_apply", Path()).is_dir():
        print("ERROR: A rebase or git-am operation is currently in progress.")
        print("Finish or abort it before saving feature patches.")
        return 1
    if paths.get("merge_head", Path()).is_file():
        print("ERROR: A merge is currently in progress.")
        print("Finish or abort it before saving feature patches.")
        return 1
    if paths.get("cherry_pick_head", Path()).is_file():
        print("ERROR: A cherry-pick is currently in progress.")
        print("Finish or abort it before saving feature patches.")
        return 1

    resolved_base_ref = resolve_base_ref(base_ref)
    cp = git(["rev-parse", "--verify", resolved_base_ref], check=False, quiet=True)
    if cp.returncode != 0:
        print(f"ERROR: Base ref does not exist: {resolved_base_ref}")
        print()
        print("Try one of:")
        print("  git fetch origin --tags")
        print(f"  {script_name} {feature_name} origin/main")
        print(f"  {script_name} {feature_name} llvmorg-19.1.0")
        return 1

    existing_patches = sorted(patch_dir.glob("*.patch"))
    existing_patch_count = len(existing_patches)
    new_commit_created = False
    selected_commits: list[str] = []
    selected_commit_set: set[str] = set()

    print("=== save feature ===")
    print(f"Feature:              {feature_name}")
    print(f"Requested base ref:   {base_ref}")
    print(f"Resolved base ref:    {resolved_base_ref}")
    print(f"Patch dir:            {patch_dir}")
    print(f"Existing patch count: {existing_patch_count}")
    print()

    status = git_output(["status", "--porcelain"], check=False)
    if status:
        print("Found uncommitted changes.")
        print("Creating a commit before saving patches...")
        git(["add", "-A"])
        diff = git(["diff", "--cached", "--quiet"], check=False, quiet=True)
        if diff.returncode == 0:
            print("No staged changes after git add.")
        elif diff.returncode == 1:
            if existing_patch_count > 0:
                commit_message = os.environ.get("COMMIT_MSG", default_update_message)
            else:
                commit_message = os.environ.get("COMMIT_MSG", default_add_message)
            git(["commit", "-m", commit_message])
            new_commit_created = True
        else:
            print("ERROR: Failed to check staged changes.")
            return 1
    else:
        print("No uncommitted changes found.")

    tmp_patch_dir = Path(tempfile.mkdtemp(prefix="clang-mg-save-feature-"))
    try:
        if existing_patch_count > 0:
            print()
            print("Existing patches found.")
            print("Finding this feature's already-applied commits by patch-id instead of using the last commits on HEAD.")

            history_commits = git_lines(["rev-list", "--reverse", f"{resolved_base_ref}..HEAD"])
            commit_by_patch_id: dict[str, list[str]] = {}
            for commit in history_commits:
                patch_id = patch_id_from_commit(commit)
                if not patch_id:
                    continue
                commit_by_patch_id.setdefault(patch_id, []).append(commit)

            missing_patch_matches: list[str] = []
            for patch in existing_patches:
                patch_id = patch_id_from_file(patch)
                candidate = ""
                if patch_id and patch_id in commit_by_patch_id:
                    for mapped_commit in commit_by_patch_id[patch_id]:
                        if mapped_commit not in selected_commit_set:
                            candidate = mapped_commit
                            break
                if not candidate:
                    missing_patch_matches.append(patch.name)
                    continue
                add_commit_if_missing(selected_commits, selected_commit_set, candidate)

            if missing_patch_matches:
                print()
                print("ERROR: Could not safely find the applied commit(s) for these existing patch file(s):")
                for patch_name in missing_patch_matches:
                    print(f"  {patch_name}")
                print()
                print("The patch folder was not modified.")
                print("Make sure the feature's current patches are applied to this LLVM checkout before saving.")
                return 1

            for commit in history_commits:
                subject = git_output(["show", "-s", "--format=%s", commit])
                if subject in {default_add_message, default_update_message}:
                    add_commit_if_missing(selected_commits, selected_commit_set, commit)

            if new_commit_created:
                add_commit_if_missing(selected_commits, selected_commit_set, git_output(["rev-parse", "HEAD"]))

            if not selected_commits:
                print()
                print("ERROR: No commits were selected for this feature.")
                print("The patch folder was not modified.")
                return 1

            print()
            print("Saving these commits as the updated feature patch stack:")
            write_selected_commit_list(selected_commits)
            save_selected_commits_as_patches(selected_commits, tmp_patch_dir)
        else:
            if new_commit_created:
                print()
                print("No existing patches found.")
                print("Saving the new feature commit as the first patch.")
                git(["format-patch", "--zero-commit", "-1", "-o", str(tmp_patch_dir)])
            else:
                commits_since_base_text = git_output(["rev-list", "--count", f"{resolved_base_ref}..HEAD"])
                commits_since_base = int(commits_since_base_text)
                if commits_since_base == 0:
                    print()
                    print("ERROR: There are no commits to save for this feature.")
                    print("Make changes first, then run:")
                    print(f"  {script_name} {feature_name} {resolved_base_ref}")
                    return 1
                print()
                print("No existing patches found.")
                print(f"No new commit was created, so saving commits from {resolved_base_ref}..HEAD.")
                print("WARNING: This can include other feature commits if this checkout already has patch stacks applied.")
                git(["format-patch", "--zero-commit", resolved_base_ref, "-o", str(tmp_patch_dir)])

        new_patches = sorted(tmp_patch_dir.glob("*.patch"))
        if not new_patches:
            print()
            print("ERROR: No patch files were generated.")
            return 1

        if existing_patch_count > 0:
            backup_dir = Path(str(patch_dir) + f".backup.{timestamp()}")
            backup_dir.mkdir(parents=True, exist_ok=True)
            for patch in existing_patches:
                shutil.copy2(patch, backup_dir / patch.name)
            print()
            print("Backed up previous patches to:")
            print(f"  {backup_dir}")

        for p in patch_dir.glob("*.patch"):
            p.unlink()
        for p in new_patches:
            shutil.copy2(p, patch_dir / p.name)

        print()
        print(f"Saved patches for feature: {feature_name}")
        print(f"Patch dir: {patch_dir}")
        print()
        for p in sorted(patch_dir.glob("*.patch")):
            print(str(p))
        return 0
    finally:
        shutil.rmtree(tmp_patch_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
