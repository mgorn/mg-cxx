#!/usr/bin/env python3
from __future__ import annotations

import sys
from clang_mg_common import git


def main(argv: list[str]) -> int:
    if argv and argv[0] in {"-h", "--help"}:
        print("Usage: scripts/reset-llvm.py [base-ref]")
        return 0
    base_ref = argv[0] if argv else "origin/main"
    print(f"Resetting LLVM checkout to: {base_ref}")

    git(["am", "--abort"], check=False, quiet=True)
    git(["rebase", "--abort"], check=False, quiet=True)
    git(["merge", "--abort"], check=False, quiet=True)

    git(["checkout", "main"])
    git(["fetch", "origin"])
    git(["reset", "--hard", base_ref])
    git(["clean", "-fd"])

    print("LLVM checkout reset.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
