#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from clang_mg_common import ensure_git_available, git, mkdir_parent


def usage() -> None:
    print("Usage: scripts/clone-llvm.py <llvm-url> <llvm-ref> <llvm-dir>")


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[0] in {"-h", "--help"}:
        usage()
        return 0 if argv and argv[0] in {"-h", "--help"} else 1

    llvm_url, llvm_ref, llvm_dir_text = argv
    llvm_dir = Path(llvm_dir_text)
    ensure_git_available()

    if not (llvm_dir / ".git").is_dir():
        print("Cloning LLVM...")
        mkdir_parent(llvm_dir)
        git(["clone", llvm_url, str(llvm_dir)])
    else:
        print("LLVM checkout already exists.")

    print("Fetching LLVM updates...")
    git(["fetch", "origin", "--tags"], cwd=llvm_dir)

    print(f"Checking out LLVM ref: {llvm_ref}")
    git(["checkout", llvm_ref], cwd=llvm_dir)

    print("Resetting working tree...")
    git(["reset", "--hard"], cwd=llvm_dir)

    print("Creating clang-mg build branch...")
    git(["checkout", "-B", "clang-mg-build"], cwd=llvm_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
