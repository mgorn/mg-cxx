#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from clang_mg_common import env_or_default, git, git_in_progress_paths, git_output, root_from_script, timestamp


def usage(script_name: str, llvm_dir: Path, work_dir: Path) -> None:
    print("Usage:")
    print(f"  scripts/{script_name} [base-ref]")
    print()
    print("Examples:")
    print(f"  scripts/{script_name}")
    print(f"  scripts/{script_name} origin/main")
    print(f"  scripts/{script_name} HEAD~12")
    print()
    print("This writes one collapsed patch containing the net LLVM checkout changes from:")
    print("  merge-base(<base-ref>, HEAD)..HEAD")
    print()
    print("Normally, use the top-level command instead:")
    print("  python build.py export")
    print("  python build.py export origin/main")
    print()
    print("Environment variables:")
    print(f"  LLVM_DIR={llvm_dir}")
    print(f"  WORK_DIR={work_dir}")


def fail(message: str) -> int:
    print(message)
    return 1


def ensure_no_git_operation_in_progress(llvm_dir: Path) -> bool:
    paths = git_in_progress_paths(llvm_dir)
    if paths.get("rebase_merge", Path()).is_dir():
        print("ERROR: A rebase is currently in progress.")
        print("Finish or abort it before exporting a net patch.")
        return False
    if paths.get("rebase_apply", Path()).is_dir():
        print("ERROR: A git-am or rebase-apply operation is currently in progress.")
        print("Finish or abort it before exporting a net patch.")
        return False
    if paths.get("merge_head", Path()).is_file():
        print("ERROR: A merge is currently in progress.")
        print("Finish or abort it before exporting a net patch.")
        return False
    if paths.get("cherry_pick_head", Path()).is_file():
        print("ERROR: A cherry-pick is currently in progress.")
        print("Finish or abort it before exporting a net patch.")
        return False
    return True


def resolve_default_base_ref(llvm_dir: Path) -> str:
    llvm_ref = env_or_default("LLVM_REF", "main")
    cp = git(["rev-parse", "--verify", f"origin/{llvm_ref}^{{commit}}"], cwd=llvm_dir, check=False, capture=True)
    if cp.returncode == 0:
        return f"origin/{llvm_ref}"
    return llvm_ref


def resolve_commit(llvm_dir: Path, ref: str) -> str | None:
    cp = git(["rev-parse", "--verify", f"{ref}^{{commit}}"], cwd=llvm_dir, check=False, capture=True)
    if cp.returncode != 0:
        return None
    value = (cp.stdout or "").strip()
    return value or None


def export_net_patch(root_dir: Path, llvm_dir: Path, work_dir: Path, base_ref: str) -> int:
    patch_root = root_dir / "patches"
    out_file = work_dir / f"clang-mg-net-changes-{timestamp()}.patch"

    print("=== export clang-mg net patch ===")
    print(f"Root dir:   {root_dir}")
    print(f"LLVM dir:   {llvm_dir}")
    print(f"Patch root: {patch_root}")
    print(f"Base ref:   {base_ref}")
    print(f"Output:     {out_file}")
    print()

    if not (llvm_dir / ".git").is_dir():
        return fail(f"ERROR: LLVM repo is not cloned:\n{llvm_dir}")
    if not ensure_no_git_operation_in_progress(llvm_dir):
        return 1

    base_commit = resolve_commit(llvm_dir, base_ref)
    if base_commit is None:
        print(f"ERROR: Base ref does not exist: {base_ref}")
        print("No patch was written.")
        return 1

    head_commit = resolve_commit(llvm_dir, "HEAD")
    if head_commit is None:
        print("ERROR: Could not resolve HEAD.")
        print("No patch was written.")
        return 1

    merge_base = git_output(["merge-base", base_commit, head_commit], cwd=llvm_dir, check=False).strip()
    if not merge_base:
        print(f"ERROR: Could not find a merge-base between {base_ref} and HEAD.")
        print("No patch was written.")
        return 1

    status = git_output(["status", "--porcelain"], cwd=llvm_dir, check=False)
    if status:
        print("ERROR: LLVM has uncommitted changes.")
        print()
        print("The export command only writes the net committed changes from the applied patch stack.")
        print("Commit, save, stash, or reset working-tree changes first so the export is exact.")
        print()
        print("Useful commands:")
        print("  git status")
        print("  python3 build.py save")
        print("  git stash push -u")
        print("  git reset --hard")
        print()
        print("No patch was written.")
        return 1

    diff_quiet = git(["diff", "--quiet", merge_base, "HEAD", "--"], cwd=llvm_dir, check=False, quiet=True)
    if diff_quiet.returncode == 0:
        print(f"No committed changes found from {merge_base}..HEAD.")
        print("No patch was written.")
        return 0
    if diff_quiet.returncode != 1:
        print("ERROR: Failed while checking for changes to export.")
        print("No patch was written.")
        return 1

    work_dir.mkdir(parents=True, exist_ok=True)
    with out_file.open("wb") as f:
        cp = subprocess.run(
            ["git", "diff", "--binary", "--find-renames", "--full-index", merge_base, "HEAD", "--"],
            cwd=str(llvm_dir),
            stdout=f,
            stderr=subprocess.PIPE,
        )
    if cp.returncode != 0:
        try:
            out_file.unlink()
        except FileNotFoundError:
            pass
        if cp.stderr:
            sys.stderr.buffer.write(cp.stderr)
        print("ERROR: Failed to write net patch.")
        return 1

    commit_count_text = git_output(["rev-list", "--count", f"{merge_base}..HEAD"], cwd=llvm_dir, check=False)
    commit_count = commit_count_text.strip() or "0"
    stat = git_output(["diff", "--stat", merge_base, "HEAD", "--"], cwd=llvm_dir, check=False)

    print("Exported net patch:")
    print(f"  {out_file}")
    print()
    print(f"Base commit: {merge_base}")
    print(f"HEAD commit: {head_commit}")
    print(f"Commits included: {commit_count}")
    if stat:
        print()
        print("Diff stat:")
        print(stat)
    return 0


def main(argv: list[str]) -> int:
    script_name = Path(__file__).name
    root_dir = root_from_script(__file__)
    work_dir = Path(env_or_default("WORK_DIR", root_dir / "work"))
    llvm_dir = Path(env_or_default("LLVM_DIR", work_dir / "llvm-project"))

    if argv and argv[0] in {"-h", "--help"}:
        usage(script_name, llvm_dir, work_dir)
        return 0
    if len(argv) > 1:
        usage(script_name, llvm_dir, work_dir)
        return 1

    base_ref = argv[0] if argv and argv[0].strip() else resolve_default_base_ref(llvm_dir)
    return export_net_patch(root_dir, llvm_dir, work_dir, base_ref)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
