#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from clang_mg_common import env_or_default, git, git_in_progress_paths, git_output, root_from_script, run


DEFAULT_OLLAMA_MODEL = "gemma3:4b"
FALLBACK_OLLAMA_MODEL = "gemma4b"


def fail(message: str) -> int:
    print(message)
    return 1


def prompt_yes_no(prompt: str, default: bool = False) -> bool:
    suffix = " [Y/n] " if default else " [y/N] "
    while True:
        try:
            answer = input(prompt + suffix).strip().lower()
        except EOFError:
            print()
            return default
        if not answer:
            return default
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Please answer yes or no.")


def prompt_text(prompt: str, default: str = "") -> str:
    if default:
        print(f"{prompt}")
        print(f"  Default: {default}")
        try:
            value = input("  Enter new value, or press Enter to keep default: ").strip()
        except EOFError:
            print()
            return default
        return value or default
    while True:
        try:
            value = input(f"{prompt}: ").strip()
        except EOFError:
            print()
            value = ""
        if value:
            return value
        print("A value is required.")


def prompt_multiline(prompt: str, default: str = "") -> str:
    print(prompt)
    if default.strip():
        print()
        print("Current description:")
        print("---")
        print(default.rstrip())
        print("---")
        print()
        print("Press Enter on the first line to keep it.")
    print("Enter description lines. Finish with a single '.' line.")
    lines: list[str] = []
    first = True
    while True:
        try:
            line = input()
        except EOFError:
            print()
            break
        if first and line == "" and default.strip():
            return default.strip()
        first = False
        if line == ".":
            break
        lines.append(line)
    return "\n".join(lines).strip()


def ensure_no_git_operation_in_progress(llvm_dir: Path) -> bool:
    paths = git_in_progress_paths(llvm_dir)
    if paths.get("rebase_merge", Path()).is_dir():
        print("ERROR: A rebase is currently in progress.")
        print("Finish or abort it before saving patches.")
        return False
    if paths.get("rebase_apply", Path()).is_dir():
        print("ERROR: A git-am or rebase-apply operation is currently in progress.")
        print("Finish or abort it before saving patches.")
        return False
    if paths.get("merge_head", Path()).is_file():
        print("ERROR: A merge is currently in progress.")
        print("Finish or abort it before saving patches.")
        return False
    if paths.get("cherry_pick_head", Path()).is_file():
        print("ERROR: A cherry-pick is currently in progress.")
        print("Finish or abort it before saving patches.")
        return False
    return True


def run_cmd(args: list[str], *, cwd: Path | None = None, input_text: str | None = None,
            timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=str(cwd) if cwd else None, input=input_text, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)


def ollama_installed() -> bool:
    return shutil.which("ollama") is not None


def ollama_running() -> bool:
    try:
        cp = run_cmd(["ollama", "list"], timeout=6)
    except Exception:
        return False
    return cp.returncode == 0


def start_ollama_server() -> bool:
    print("Starting Ollama with `ollama serve`...")
    try:
        kwargs: dict[str, object] = {
            "stdout": subprocess.DEVNULL,
            "stderr": subprocess.DEVNULL,
            "stdin": subprocess.DEVNULL,
        }
        if os.name == "nt":
            kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP  # type: ignore[attr-defined]
        else:
            kwargs["start_new_session"] = True
        subprocess.Popen(["ollama", "serve"], **kwargs)
    except Exception as exc:
        print(f"ERROR: Failed to start Ollama: {exc}")
        return False

    for _ in range(20):
        if ollama_running():
            print("Ollama is running.")
            return True
        time.sleep(0.5)
    print("Ollama did not become ready in time.")
    return False


def installed_ollama_models() -> list[str]:
    try:
        cp = run_cmd(["ollama", "list"], timeout=10)
    except Exception:
        return []
    if cp.returncode != 0:
        return []
    models: list[str] = []
    for i, line in enumerate((cp.stdout or "").splitlines()):
        line = line.strip()
        if not line or i == 0 and line.lower().startswith("name"):
            continue
        parts = line.split()
        if parts:
            models.append(parts[0])
    return models


def preferred_model(models: list[str]) -> str:
    env_model = os.environ.get("OLLAMA_MODEL", "").strip()
    if env_model:
        return env_model
    for candidate in (DEFAULT_OLLAMA_MODEL, FALLBACK_OLLAMA_MODEL, "gemma:4b"):
        if candidate in models:
            return candidate
    for model in models:
        lowered = model.lower()
        if "gemma" in lowered and "4b" in lowered:
            return model
    return models[0] if models else DEFAULT_OLLAMA_MODEL


def select_ollama_model(models: list[str]) -> str:
    default = preferred_model(models)
    if not models:
        return default
    print()
    print("Installed Ollama models:")
    for idx, model in enumerate(models, start=1):
        marker = " (default)" if model == default else ""
        print(f"  {idx}) {model}{marker}")
    print()
    while True:
        try:
            answer = input(f"Choose a model, or press Enter for {default}: ").strip()
        except EOFError:
            print()
            return default
        if not answer:
            return default
        if answer.isdigit():
            idx = int(answer)
            if 1 <= idx <= len(models):
                return models[idx - 1]
        if answer in models:
            return answer
        print("Unknown model selection.")


def truncate(text: str, max_chars: int) -> str:
    if len(text) <= max_chars:
        return text
    return text[:max_chars] + "\n\n[diff truncated]\n"


def collect_change_summary(llvm_dir: Path) -> str:
    status = git_output(["status", "--short"], cwd=llvm_dir, check=False)
    name_status = git_output(["diff", "--name-status"], cwd=llvm_dir, check=False)
    stat = git_output(["diff", "--stat"], cwd=llvm_dir, check=False)
    diff = git_output(["diff", "--"], cwd=llvm_dir, check=False)
    return f"""Git status:
{status}

Changed files:
{name_status}

Diff stat:
{stat}

Diff:
{truncate(diff, 14000)}
"""


def parse_ai_message(text: str) -> tuple[str, str]:
    cleaned = text.strip()
    if not cleaned:
        return "", ""

    # Accept JSON if the model returns it despite the plain-text request.
    try:
        data = json.loads(cleaned)
        subject = str(data.get("subject") or data.get("message") or "").strip()
        description = str(data.get("description") or data.get("body") or "").strip()
        return subject, description
    except Exception:
        pass

    subject = ""
    description = ""
    lines = cleaned.splitlines()
    in_description = False
    desc_lines: list[str] = []
    for line in lines:
        if re.match(r"^subject\s*:", line, flags=re.IGNORECASE):
            subject = re.sub(r"^subject\s*:\s*", "", line, flags=re.IGNORECASE).strip()
            in_description = False
            continue
        if re.match(r"^(description|body)\s*:", line, flags=re.IGNORECASE):
            after = re.sub(r"^(description|body)\s*:\s*", "", line, flags=re.IGNORECASE).strip()
            if after:
                desc_lines.append(after)
            in_description = True
            continue
        if in_description:
            desc_lines.append(line)

    description = "\n".join(desc_lines).strip()
    if not subject:
        subject = lines[0].strip().strip('"') if lines else ""
        rest = lines[1:]
        if not description and rest:
            description = "\n".join(rest).strip()
    subject = re.sub(r"^[-*\s]+", "", subject).strip()
    return subject, description


def generate_ai_message(llvm_dir: Path, model: str) -> tuple[str, str]:
    change_summary = collect_change_summary(llvm_dir)
    prompt = f"""You are helping maintain a patch stack for a modified LLVM/Clang fork named clang-mg.
Create a concise Git patch commit message for the uncommitted changes below.

Rules:
- The subject must be one line, imperative mood, no trailing period.
- Prefer the prefix "clang-mg:" unless a narrower prefix is obvious.
- The description should be 2-5 short lines explaining what changed and why.
- Do not invent details not supported by the diff.
- Return exactly this format:
Subject: <subject>
Description:
<description>

Changes:
{change_summary}
"""
    try:
        cp = run_cmd(["ollama", "run", model, prompt], timeout=120)
    except subprocess.TimeoutExpired:
        print("Ollama timed out while generating a message.")
        return "", ""
    except Exception as exc:
        print(f"Ollama failed: {exc}")
        return "", ""
    if cp.returncode != 0:
        print("Ollama failed to generate a message.")
        if cp.stderr:
            print(cp.stderr.strip())
        return "", ""
    return parse_ai_message(cp.stdout or "")


def maybe_generate_ai_message(llvm_dir: Path) -> tuple[str, str]:
    if not sys.stdin.isatty():
        return "", ""
    if not ollama_installed():
        print("Ollama is not installed or is not available in PATH.")
        return "", ""

    if not ollama_running():
        print("Ollama is installed, but it does not appear to be running.")
        if prompt_yes_no("Start Ollama now?", default=False):
            if not start_ollama_server():
                return "", ""
        else:
            return "", ""

    if not ollama_running():
        return "", ""

    if not prompt_yes_no("Use an AI-generated commit message as a starting point?", default=True):
        return "", ""

    models = installed_ollama_models()
    if not models:
        print("No installed Ollama models were found. Continuing with manual entry.")
        return "", ""

    model = select_ollama_model(models)
    print()
    print(f"Generating commit message with Ollama model: {model}")
    subject, description = generate_ai_message(llvm_dir, model)
    if subject or description:
        print()
        print("AI-generated starting point:")
        print("---")
        if subject:
            print(subject)
        if description:
            print()
            print(description)
        print("---")
    return subject, description


def sanitize_subject(subject: str) -> str:
    subject = subject.strip()
    if not subject:
        return "clang-mg: update patches"
    return subject


def slugify(subject: str) -> str:
    text = subject.lower()
    text = re.sub(r"^\[patch[^\]]*\]\s*", "", text)
    text = re.sub(r"^clang-mg:\s*", "", text)
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text[:70].strip("-") or "update-patches"


def existing_patch_numbers(patch_root: Path) -> list[int]:
    numbers: list[int] = []
    for p in patch_root.glob("*.patch"):
        m = re.match(r"^(\d+)-", p.name)
        if m:
            try:
                numbers.append(int(m.group(1)))
            except ValueError:
                pass
    return numbers


def next_patch_name(patch_root: Path, subject: str) -> str:
    numbers = existing_patch_numbers(patch_root)
    width = 4
    for p in patch_root.glob("*.patch"):
        m = re.match(r"^(\d+)-", p.name)
        if m:
            width = max(width, len(m.group(1)))
    next_num = (max(numbers) + 1) if numbers else 1
    return f"{next_num:0{width}d}-{slugify(subject)}.patch"


def write_commit_message_file(subject: str, description: str) -> Path:
    tmp = tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, prefix="clang-mg-commit-", suffix=".txt")
    with tmp:
        tmp.write(subject.strip() + "\n")
        if description.strip():
            tmp.write("\n")
            tmp.write(description.strip() + "\n")
    return Path(tmp.name)


def save_current_changes(root_dir: Path, llvm_dir: Path) -> int:
    patch_root = root_dir / "patches"

    print("=== save clang-mg patch ===")
    print(f"Root dir:   {root_dir}")
    print(f"LLVM dir:   {llvm_dir}")
    print(f"Patch root: {patch_root}")
    print()

    if not (llvm_dir / ".git").is_dir():
        return fail(f"ERROR: LLVM repo is not cloned:\n{llvm_dir}")
    if not ensure_no_git_operation_in_progress(llvm_dir):
        return 1

    status = git_output(["status", "--porcelain"], cwd=llvm_dir, check=False)
    if not status:
        print("LLVM has no uncommitted changes to save.")
        return 0

    print("Changes waiting to be saved:")
    print(status)
    print()

    ai_subject, ai_description = maybe_generate_ai_message(llvm_dir)

    print()
    subject = sanitize_subject(prompt_text("Commit message", ai_subject.strip()))
    description = prompt_multiline("Commit description", ai_description.strip())

    patch_root.mkdir(parents=True, exist_ok=True)
    message_file = write_commit_message_file(subject, description)
    tmp_dir = Path(tempfile.mkdtemp(prefix=".patch-save.", dir=str(root_dir)))
    try:
        git(["add", "-A"], cwd=llvm_dir)
        git(["commit", "-F", str(message_file)], cwd=llvm_dir)

        cp = git([
            "format-patch",
            "--zero-commit",
            "--no-stat",
            "-1",
            "--output-directory",
            str(tmp_dir),
        ], cwd=llvm_dir, check=False, quiet=True)
        if cp.returncode != 0:
            print("ERROR: Failed to generate patch from the new commit.")
            return 1

        generated = sorted(tmp_dir.glob("*.patch"))
        if not generated:
            print("ERROR: No patch was generated from the new commit.")
            return 1

        patch_name = next_patch_name(patch_root, subject)
        target = patch_root / patch_name
        while target.exists():
            stem = target.stem
            target = patch_root / f"{stem}-new.patch"
        shutil.copy2(generated[0], target)

        print()
        print("Saved patch:")
        print(f"  {target}")
        print()
        print("Created LLVM commit:")
        print(f"  {git_output(['rev-parse', '--short', 'HEAD'], cwd=llvm_dir, check=False)} {subject}")
        return 0
    finally:
        try:
            message_file.unlink()
        except FileNotFoundError:
            pass
        shutil.rmtree(tmp_dir, ignore_errors=True)


def main(argv: list[str]) -> int:
    root_dir = root_from_script(__file__)
    work_dir = Path(env_or_default("WORK_DIR", root_dir / "work"))
    llvm_dir = Path(env_or_default("LLVM_DIR", work_dir / "llvm-project"))

    if argv and argv[0] in {"-h", "--help"}:
        print("Usage:")
        print("  scripts/save-patches.py")
        print()
        print("Normally, use:")
        print("  python build.py save")
        return 0

    return save_current_changes(root_dir, llvm_dir)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
