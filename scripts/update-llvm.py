#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from clang_mg_common import env_or_default, git, git_in_progress_paths, git_output, root_from_script, run


def main(argv: list[str]) -> int:
    if argv and argv[0] in {"-h", "--help"}:
        print("Usage: scripts/update-llvm.py")
        return 0

    root_dir = root_from_script(__file__)
    script_dir = Path(__file__).resolve().parent

    llvm_url = env_or_default("LLVM_URL", "https://github.com/llvm/llvm-project.git")
    llvm_ref = env_or_default("LLVM_REF", "main")
    work_dir = Path(env_or_default("WORK_DIR", root_dir / "work"))
    llvm_dir = Path(env_or_default("LLVM_DIR", work_dir / "llvm-project"))
    clone_script = script_dir / "clone-llvm.py"

    print("=== update LLVM ===")
    print(f"LLVM ref:  {llvm_ref}")
    print(f"LLVM dir:  {llvm_dir}")
    print()

    if not (llvm_dir / ".git").is_dir():
        print("LLVM is not cloned yet.")
        if not clone_script.is_file():
            print("ERROR: clone script not found:")
            print(str(clone_script))
            return 1
        print("Calling clone-llvm.py...")
        return run([sys.executable, str(clone_script), llvm_url, llvm_ref, str(llvm_dir)], check=False).returncode

    print("Checking LLVM working tree...")
    paths = git_in_progress_paths(llvm_dir)
    if paths.get("rebase_merge", Path()).is_dir() or paths.get("rebase_apply", Path()).is_dir():
        print("ERROR: A rebase is currently in progress.")
        print("Finish or abort it before updating LLVM.")
        return 1
    if paths.get("merge_head", Path()).is_file():
        print("ERROR: A merge is currently in progress.")
        print("Finish or abort it before updating LLVM.")
        return 1
    if paths.get("cherry_pick_head", Path()).is_file():
        print("ERROR: A cherry-pick or patch application is currently in progress.")
        print("Finish or abort it before updating LLVM.")
        return 1

    status = git_output(["status", "--porcelain"], cwd=llvm_dir)
    if status:
        print("ERROR: LLVM has uncommitted changes.")
        print()
        print("You may be working on a feature patch right now.")
        print("Save your feature patches before updating LLVM.")
        print()
        print("Useful commands:")
        print("  git status")
        print("  git diff")
        print("  git add .")
        print('  git commit -m "clang-mg: describe feature"')
        print(f"  ../clang-mg/scripts/save-feature.py <feature-name> {llvm_ref}")
        print()
        print("Update cancelled.")
        return 1

    print("LLVM working tree is clean.")
    print()
    print("Fetching latest LLVM changes...")
    git(["fetch", "origin", "--tags"], cwd=llvm_dir)

    current_branch = git_output(["branch", "--show-current"], cwd=llvm_dir, check=False)
    if not current_branch:
        print("LLVM checkout is detached.")
        print(f"Checking out requested ref: {llvm_ref}")
        git(["checkout", llvm_ref], cwd=llvm_dir)
        current_branch = git_output(["branch", "--show-current"], cwd=llvm_dir, check=False)
        if not current_branch:
            print("Still detached after checkout.")
            print("Fetch complete, but there is no branch to pull.")
            print("LLVM is at:")
            git(["--no-pager", "log", "--oneline", "-1"], cwd=llvm_dir)
            return 0

    print(f"Current branch: {current_branch}")
    upstream = git_output(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], cwd=llvm_dir, check=False)
    if upstream:
        print(f"Pulling from upstream: {upstream}")
        git(["pull", "--ff-only"], cwd=llvm_dir)
    else:
        print(f"No upstream is configured for branch: {current_branch}")
        cp = git(["show-ref", "--verify", "--quiet", f"refs/remotes/origin/{current_branch}"], cwd=llvm_dir, check=False, quiet=True)
        if cp.returncode == 0:
            print(f"Found matching remote branch: origin/{current_branch}")
            print("Pulling with fast-forward only...")
            git(["pull", "--ff-only", "origin", current_branch], cwd=llvm_dir)
        else:
            print("No matching remote branch found.")
            print("Fetch completed, but nothing was pulled.")
            print()
            print("You can manually update with something like:")
            print("  git checkout main")
            print("  git pull --ff-only origin main")
            return 0

    print()
    print("LLVM updated successfully.")
    git(["--no-pager", "log", "--oneline", "-1"], cwd=llvm_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
