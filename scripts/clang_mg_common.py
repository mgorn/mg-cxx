#!/usr/bin/env python3
from __future__ import annotations

import ctypes
import fnmatch
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Iterable, Sequence

TRUTHY = {"1", "true", "TRUE", "yes", "YES", "on", "ON", "enabled", "ENABLED"}
FALSY = {"0", "false", "FALSE", "no", "NO", "off", "OFF", "disabled", "DISABLED"}


def eprint(*args: object, **kwargs: object) -> None:
    print(*args, file=sys.stderr, **kwargs)


def is_windows() -> bool:
    return os.name == "nt" or platform.system().lower() == "windows"


def is_macos() -> bool:
    return platform.system() == "Darwin"


def has_cmd(name: str) -> bool:
    return shutil.which(name) is not None


def cmd_path(name: str) -> str | None:
    return shutil.which(name)


def quote_cmd(args: Sequence[str | os.PathLike[str]]) -> str:
    return " ".join(str(a) for a in args)


def run(args: Sequence[str | os.PathLike[str]], *, cwd: str | os.PathLike[str] | None = None,
        env: dict[str, str] | None = None, check: bool = True,
        capture: bool = False, quiet: bool = False, text: bool = True,
        input_data: str | bytes | None = None) -> subprocess.CompletedProcess:
    # Match shell script output ordering when stdout is redirected: print any
    # already-buffered Python text before handing the terminal to a child process.
    sys.stdout.flush()
    sys.stderr.flush()
    stdout = subprocess.PIPE if capture or quiet else None
    stderr = subprocess.PIPE if capture or quiet else None
    cp = subprocess.run([str(a) for a in args], cwd=str(cwd) if cwd is not None else None,
                        env=env, stdout=stdout, stderr=stderr, text=text, input=input_data)
    if check and cp.returncode != 0:
        if quiet and cp.stdout:
            print(cp.stdout, end="")
        if quiet and cp.stderr:
            eprint(cp.stderr, end="")
        raise SystemExit(f"{quote_cmd(args)} failed with exit code {cp.returncode}")
    return cp


def output(args: Sequence[str | os.PathLike[str]], *, cwd: str | os.PathLike[str] | None = None,
           check: bool = True, strip: bool = True) -> str:
    cp = run(args, cwd=cwd, check=check, capture=True)
    if cp.returncode != 0 and not check:
        return ""
    text = cp.stdout or ""
    return text.strip() if strip else text


def git(args: Sequence[str], *, cwd: str | os.PathLike[str] | None = None, check: bool = True,
        capture: bool = False, quiet: bool = False) -> subprocess.CompletedProcess:
    return run(["git", *args], cwd=cwd, check=check, capture=capture, quiet=quiet)


def git_output(args: Sequence[str], *, cwd: str | os.PathLike[str] | None = None, check: bool = True) -> str:
    return output(["git", *args], cwd=cwd, check=check)


def script_dir(file: str) -> Path:
    return Path(file).resolve().parent


def root_from_script(file: str) -> Path:
    return script_dir(file).parent


def env_or_default(name: str, default: str | os.PathLike[str]) -> str:
    value = os.environ.get(name, "")
    return str(default) if value.strip() == "" else value


def truthy(value: str | None) -> bool:
    return (value or "") in TRUTHY


def parse_enabled(value: str) -> bool:
    if value in TRUTHY:
        return True
    if value in FALSY:
        return False
    raise SystemExit(f"ERROR: Invalid ENABLED value: {value}\nUse one of: 1, 0, true, false, yes, no, on, off")


def default_jobs() -> str:
    value = os.environ.get("JOBS", "")
    if value.strip():
        return value
    return str(os.cpu_count() or 4)


def _uname(flag: str) -> str:
    try:
        return output(["uname", flag], check=False)
    except Exception:
        return ""


def normalized_arch() -> str:
    arch = ""
    if is_windows():
        arch = os.environ.get("PROCESSOR_ARCHITEW6432") or os.environ.get("PROCESSOR_ARCHITECTURE") or ""
    else:
        arch = _uname("-m")
    if not arch.strip():
        arch = os.environ.get("PROCESSOR_ARCHITECTURE", "")
    if not arch.strip():
        arch = platform.machine() or "unknown"
    mapping = {
        "AMD64": "x86_64", "x86_64": "x86_64",
        "ARM64": "aarch64", "arm64": "aarch64", "aarch64": "aarch64",
        "x86": "i686", "i386": "i686", "i486": "i686", "i586": "i686", "i686": "i686",
        "ARM": "arm", "arm": "arm",
    }
    if arch in mapping:
        return mapping[arch]
    if arch.startswith("armv7"):
        return "armv7"
    return arch.lower()


def detect_target_triple() -> str:
    env = os.environ.get("BUILD_TARGET_TRIPLE", "")
    if env.strip():
        return env
    for compiler in ("clang", "clang.exe", "cc", "cc.exe"):
        if not has_cmd(compiler):
            continue
        try:
            triple = output([compiler, "-dumpmachine"], check=False)
            if triple.strip():
                return triple.strip().splitlines()[0].strip()
        except Exception:
            pass
    arch = normalized_arch()
    if is_windows():
        return f"{arch}-pc-windows-msvc"
    system = _uname("-s") or platform.system()
    if system == "Darwin":
        if arch == "aarch64":
            return "arm64-apple-darwin"
        return f"{arch}-apple-darwin"
    if system == "Linux":
        if arch == "x86_64":
            return "x86_64-pc-linux-gnu"
        if arch == "aarch64":
            return "aarch64-unknown-linux-gnu"
        if arch in {"armv7", "arm"}:
            return "armv7-unknown-linux-gnueabihf"
        return f"{arch}-unknown-linux-gnu"
    if system.startswith(("MINGW", "MSYS", "CYGWIN")):
        return f"{arch}-pc-windows-msvc"
    return f"{arch}-unknown-{system or 'platform'}"


def mkdir_parent(path: str | os.PathLike[str]) -> None:
    parent = Path(path).parent
    if str(parent):
        parent.mkdir(parents=True, exist_ok=True)


def list_patch_features(patch_root: Path) -> list[str]:
    if not patch_root.is_dir():
        return []
    return sorted(p.name for p in patch_root.iterdir() if p.is_dir())


def write_default_feature_config(config_file: Path, feature_name: str) -> None:
    config_file.parent.mkdir(parents=True, exist_ok=True)
    config_file.write_text(f"""# Auto-generated config for clang-mg feature: {feature_name}

# Whether this feature should be applied.
# Valid values: 1, 0, true, false, yes, no, on, off
ENABLED=1

# Features that must be applied before this feature.
# Example:
#   DEPENDS=(core)
DEPENDS=()

# Features that this feature must be applied before.
# Usually DEPENDS is enough, but this is useful for ordering from the other side.
# Example:
#   BEFORE=(if-constexpr-members)
BEFORE=()
""", encoding="utf-8")


def is_ignored_patch_dir_name(name: str) -> bool:
    return (
        fnmatch.fnmatch(name, "*.backup.*") or
        fnmatch.fnmatch(name, "*.bak.*") or
        fnmatch.fnmatch(name, "*.old.*") or
        name in {".backup", ".backups", "backup", "backups"} or
        fnmatch.fnmatch(name, ".patch-refresh-*") or
        fnmatch.fnmatch(name, "*~")
    )


def remove_inline_comment(text: str) -> str:
    return re.sub(r"\s+#.*$", "", text).strip()


def normalize_config_value(value: str) -> str:
    value = remove_inline_comment(value)
    if len(value) >= 2 and ((value[0] == value[-1] == '"') or (value[0] == value[-1] == "'")):
        value = value[1:-1]
    return value.strip()


def parse_name_list(text: str) -> list[str]:
    clean = remove_inline_comment(text)
    if not clean.strip():
        return []
    items: list[str] = []
    for m in re.finditer(r'"([^\"]*)"|\'([^\']*)\'|([^\s]+)', clean):
        item = next(g for g in m.groups() if g is not None).strip()
        if item:
            items.append(item)
    return items


def read_feature_config(config_file: Path) -> dict[str, object]:
    enabled = "1"
    depends: list[str] = []
    before: list[str] = []
    for line in config_file.read_text(encoding="utf-8", errors="replace").splitlines():
        trimmed = line.strip()
        if not trimmed or trimmed.startswith("#"):
            continue
        m = re.match(r"^ENABLED\s*=\s*(.+?)\s*$", trimmed)
        if m:
            enabled = normalize_config_value(m.group(1))
            continue
        m = re.match(r"^DEPENDS\s*=\s*\((.*)\)\s*$", trimmed)
        if m:
            depends = parse_name_list(m.group(1))
            continue
        m = re.match(r"^BEFORE\s*=\s*\((.*)\)\s*$", trimmed)
        if m:
            before = parse_name_list(m.group(1))
            continue
        m = re.match(r"^DEPENDS\s*=\s*(.+?)\s*$", trimmed)
        if m:
            depends = parse_name_list(m.group(1))
            continue
        m = re.match(r"^BEFORE\s*=\s*(.+?)\s*$", trimmed)
        if m:
            before = parse_name_list(m.group(1))
            continue
    return {"enabled": enabled, "depends": depends, "before": before}


def git_dir(cwd: str | os.PathLike[str] | None = None) -> Path | None:
    cp = git(["rev-parse", "--git-dir"], cwd=cwd, check=False, capture=True)
    if cp.returncode != 0 or not (cp.stdout or "").strip():
        return None
    raw = (cp.stdout or "").splitlines()[0].strip()
    p = Path(raw)
    if not p.is_absolute():
        p = Path(cwd or os.getcwd()) / p
    return p.resolve()


def git_in_progress_paths(cwd: str | os.PathLike[str] | None = None) -> dict[str, Path]:
    gd = git_dir(cwd)
    if gd is None:
        return {}
    return {
        "git_dir": gd,
        "rebase_merge": gd / "rebase-merge",
        "rebase_apply": gd / "rebase-apply",
        "merge_head": gd / "MERGE_HEAD",
        "cherry_pick_head": gd / "CHERRY_PICK_HEAD",
        "apply_feature_state": gd / "clang-mg-apply-feature-state",
    }


def ensure_git_available() -> None:
    if not has_cmd("git"):
        raise SystemExit("git was not found. Please install Git and make sure it is available in PATH.")


def copy_glob(pattern: str | os.PathLike[str], dest: str | os.PathLike[str]) -> None:
    d = Path(dest)
    d.mkdir(parents=True, exist_ok=True)
    for p in sorted(Path().glob(str(pattern))):
        shutil.copy2(p, d / p.name)


def timestamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def remove_files(paths: Iterable[Path]) -> None:
    for p in paths:
        try:
            p.unlink()
        except FileNotFoundError:
            pass
