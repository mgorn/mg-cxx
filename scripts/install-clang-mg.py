#!/usr/bin/env python3
from __future__ import annotations

import ctypes
import os
import platform
import re
import subprocess
import sys
from pathlib import Path

from clang_mg_common import env_or_default, is_macos, is_windows, root_from_script, run

MARKER_BEGIN = "# >>> clang-mg path >>>"
MARKER_END = "# <<< clang-mg path <<<"
LEGACY_MARKER = "# Added by build-clang-mg.sh"


def show_usage(build_dir: Path, path_scope: str) -> None:
    print("Usage:")
    print("  scripts/install-clang-mg.py [clang-mg-executable | build-dir | bin-dir]")
    print()
    print("Examples:")
    print("  scripts/install-clang-mg.py")
    print("  scripts/install-clang-mg.py work/build/bin/clang-mg.exe")
    print("  scripts/install-clang-mg.py work/build")
    print("  scripts/install-clang-mg.py work/build/bin")
    print()
    print("Environment variables:")
    print("  CLANG_SUFFIX=mg")
    print(f"  BUILD_DIR={build_dir}")
    print("  PROFILE_FILE=<custom shell/profile path>")
    print("  CLANG_MG_PATH_SCOPE=Auto|User|Machine|Global|Both")
    print()
    print("Windows behavior:")
    print("  Auto:")
    print("    Uses Machine PATH if running as Administrator.")
    print("    If not elevated, asks to elevate through UAC.")
    print("    If elevation is declined, falls back to User PATH.")
    print()
    print("  Machine / Global:")
    print("    Adds clang-mg to the machine-wide PATH.")
    print("    If not elevated, asks to elevate through UAC.")
    print()
    print("  User:")
    print("    Adds clang-mg to the persistent PATH for the current Windows user.")
    print()
    print("  Both:")
    print("    Adds clang-mg to User PATH.")
    print("    Also asks to elevate for Machine PATH if needed.")
    print()
    print("Important:")
    print("  Existing cmd.exe windows do not update their PATH after this script runs.")
    print("  Open a brand-new terminal after install.")


def shell_name() -> str:
    sh = os.environ.get("SHELL", "")
    if sh:
        return Path(sh).name
    if is_windows():
        return "powershell"
    return "sh"


def detected_shell_profile() -> Path:
    name = shell_name()
    home = Path.home()
    if name == "zsh":
        return home / ".zshrc"
    if name == "bash":
        if is_macos():
            return home / ".bash_profile"
        return home / ".bashrc"
    if name == "fish":
        return home / ".config" / "fish" / "config.fish"
    if is_windows():
        return Path(os.environ.get("PROFILE", str(home / "Documents" / "PowerShell" / "Microsoft.PowerShell_profile.ps1")))
    return home / ".profile"


def resolve_full_path_loose(path: str | Path) -> Path:
    p = Path(path)
    if p.is_absolute():
        return p.resolve(strict=False)
    return (Path.cwd() / p).resolve(strict=False)


def clang_exe_candidates_in_dir(directory: Path, exe_base_name: str) -> list[Path]:
    if is_windows():
        return [directory / f"{exe_base_name}.exe", directory / exe_base_name]
    return [directory / exe_base_name, directory / f"{exe_base_name}.exe"]


def resolve_clang_exe_path(input_path: str, build_dir: Path, exe_base_name: str) -> Path:
    if not input_path.strip():
        bin_dir = build_dir / "bin"
        for candidate in clang_exe_candidates_in_dir(bin_dir, exe_base_name):
            if candidate.is_file():
                return resolve_full_path_loose(candidate)
        return resolve_full_path_loose(bin_dir / (f"{exe_base_name}.exe" if is_windows() else exe_base_name))

    full_input = resolve_full_path_loose(input_path)
    if full_input.is_dir():
        nested_bin = full_input / "bin"
        if nested_bin.is_dir():
            for candidate in clang_exe_candidates_in_dir(nested_bin, exe_base_name):
                if candidate.is_file():
                    return resolve_full_path_loose(candidate)
        for candidate in clang_exe_candidates_in_dir(full_input, exe_base_name):
            if candidate.is_file():
                return resolve_full_path_loose(candidate)
    return full_input


def comparable_path(path: str | Path) -> str:
    p = resolve_full_path_loose(path)
    text = str(p).rstrip("\\/")
    return text.lower() if is_windows() else text


def path_list_contains_dir(path_value: str | None, directory: Path) -> bool:
    if not path_value:
        return False
    target = comparable_path(directory)
    for part in path_value.split(os.pathsep):
        if not part.strip():
            continue
        try:
            if comparable_path(part) == target:
                return True
        except Exception:
            pass
    return False


def add_dir_to_current_process_path(bin_dir: Path) -> None:
    if not path_list_contains_dir(os.environ.get("PATH", ""), bin_dir):
        current = os.environ.get("PATH", "")
        os.environ["PATH"] = str(bin_dir) if not current else f"{bin_dir}{os.pathsep}{current}"


def is_admin() -> bool:
    if not is_windows():
        return False
    try:
        return bool(ctypes.windll.shell32.IsUserAnAdmin())
    except Exception:
        return False


def can_prompt() -> bool:
    return sys.stdin.isatty()


def start_elevated_install(script_path: Path, resolved_input_path: Path, target_scope: str, clang_suffix: str, build_dir: Path) -> bool:
    if not is_windows():
        return False
    try:
        env = os.environ
        env["CLANG_MG_PATH_SCOPE"] = target_scope
        env["CLANG_SUFFIX"] = clang_suffix
        env["BUILD_DIR"] = str(build_dir)
        params = f'"{script_path}" "{resolved_input_path}"'
        rc = ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, params, str(Path.cwd()), 1)
        return rc > 32
    except Exception as exc:
        print(f"Elevation was cancelled or failed: {exc}")
        return False


def request_elevation_for_machine_path(script_path: Path, resolved_input_path: Path, exe_base_name: str, clang_suffix: str, build_dir: Path) -> bool:
    if is_admin():
        return False
    if not can_prompt():
        print("Machine PATH install requires Administrator, but this session cannot prompt for elevation.")
        return False
    print()
    print("Adding clang-mg to the global Machine PATH requires Administrator privileges.")
    answer = input("Relaunch this installer elevated through UAC now? [Y/n]: ")
    if not answer.strip() or answer in {"y", "Y", "yes", "YES", "Yes"}:
        if start_elevated_install(script_path, resolved_input_path, "Machine", clang_suffix, build_dir):
            print()
            print("Elevated installer launched.")
            print("Approve the UAC prompt, then open a brand-new terminal and run:")
            print(f"  where {exe_base_name}")
            print(f"  {exe_base_name} --version")
            return True
    return False


def send_windows_environment_changed() -> None:
    if not is_windows():
        return
    try:
        HWND_BROADCAST = 0xFFFF
        WM_SETTINGCHANGE = 0x001A
        SMTO_ABORTIFHUNG = 0x0002
        result = ctypes.c_void_p()
        ctypes.windll.user32.SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                                                 "Environment", SMTO_ABORTIFHUNG, 5000,
                                                 ctypes.byref(result))
    except Exception:
        pass


def get_persistent_path(target_name: str) -> str:
    import winreg
    if target_name == "Machine":
        key_path = r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        root = winreg.HKEY_LOCAL_MACHINE
    else:
        key_path = r"Environment"
        root = winreg.HKEY_CURRENT_USER
    try:
        with winreg.OpenKey(root, key_path, 0, winreg.KEY_READ) as key:
            value, _typ = winreg.QueryValueEx(key, "Path")
            return value or ""
    except FileNotFoundError:
        return ""


def set_persistent_path(target_name: str, value: str) -> None:
    import winreg
    if target_name == "Machine":
        key_path = r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        root = winreg.HKEY_LOCAL_MACHINE
    else:
        key_path = r"Environment"
        root = winreg.HKEY_CURRENT_USER
    with winreg.OpenKey(root, key_path, 0, winreg.KEY_SET_VALUE) as key:
        winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, value)


def add_windows_path_target(bin_dir: Path, target_name: str) -> None:
    if target_name == "Machine" and not is_admin():
        raise RuntimeError("Machine PATH install requires Administrator.")
    current_path = get_persistent_path(target_name)
    if path_list_contains_dir(current_path, bin_dir):
        print(f"clang-mg bin directory is already in the persistent {target_name} PATH.")
    else:
        updated_path = str(bin_dir) if not current_path.strip() else f"{bin_dir}{os.pathsep}{current_path}"
        set_persistent_path(target_name, updated_path)
        print(f"Added clang-mg bin directory to the persistent {target_name} PATH.")
    verified = get_persistent_path(target_name)
    if not path_list_contains_dir(verified, bin_dir):
        raise RuntimeError(f"PATH update failed. {bin_dir} was not found in the persistent {target_name} PATH after writing it.")
    print(f"Verified persistent {target_name} PATH contains:")
    print(f"  {bin_dir}")


def add_windows_persistent_path(bin_dir: Path, resolved_input_path: Path, path_scope: str, script_path: Path, exe_base_name: str, clang_suffix: str, build_dir: Path) -> None:
    scope = path_scope.lower()
    if scope == "auto":
        if is_admin():
            add_windows_path_target(bin_dir, "Machine")
        else:
            if request_elevation_for_machine_path(script_path, resolved_input_path, exe_base_name, clang_suffix, build_dir):
                raise SystemExit(0)
            print()
            print("Falling back to persistent User PATH.")
            add_windows_path_target(bin_dir, "User")
    elif scope == "user":
        add_windows_path_target(bin_dir, "User")
    elif scope in {"machine", "global"}:
        if not is_admin():
            if request_elevation_for_machine_path(script_path, resolved_input_path, exe_base_name, clang_suffix, build_dir):
                raise SystemExit(0)
            raise RuntimeError("Machine PATH install requires Administrator and elevation was not completed.")
        add_windows_path_target(bin_dir, "Machine")
    elif scope == "both":
        add_windows_path_target(bin_dir, "User")
        if is_admin():
            add_windows_path_target(bin_dir, "Machine")
        else:
            if request_elevation_for_machine_path(script_path, resolved_input_path, exe_base_name, clang_suffix, build_dir):
                raise SystemExit(0)
            print("Machine PATH was not updated because elevation was not completed.")
    else:
        raise RuntimeError(f"Invalid CLANG_MG_PATH_SCOPE value: {path_scope}. Use Auto, User, Machine, Global, or Both.")
    add_dir_to_current_process_path(bin_dir)
    send_windows_environment_changed()
    print()
    print("Current process PATH now contains:")
    print(f"  {bin_dir}")


def escape_sh_double(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")


def escape_ps_single(value: str) -> str:
    return value.replace("'", "''")


def remove_old_blocks(file_path: Path) -> None:
    if not file_path.is_file():
        return
    name = shell_name()
    lines = file_path.read_text(encoding="utf-8", errors="replace").splitlines()
    output: list[str] = []
    in_managed = False
    in_legacy = False
    legacy_depth = 0
    for line in lines:
        if line == MARKER_BEGIN:
            in_managed = True
            continue
        if line == MARKER_END:
            in_managed = False
            continue
        if in_managed:
            continue
        if line == LEGACY_MARKER:
            in_legacy = True
            legacy_depth = 0
            continue
        if in_legacy:
            if name == "fish":
                if re.match(r"^\s*if\s+", line):
                    legacy_depth += 1
                if re.match(r"^\s*end\s*$", line):
                    legacy_depth -= 1
                    if legacy_depth <= 0:
                        in_legacy = False
                continue
            if re.match(r"^\s*if\s+\[", line):
                legacy_depth = 1
            if re.match(r"^\s*fi\s*$", line) and legacy_depth == 1:
                in_legacy = False
                continue
            continue
        output.append(line)
    file_path.write_text("\n".join(output) + ("\n" if output else ""), encoding="utf-8")


def add_profile_path_block(file_path: Path, bin_dir: Path) -> None:
    name = shell_name()
    extension = file_path.suffix.lower()
    if name == "fish" and extension != ".ps1":
        escaped = escape_sh_double(str(bin_dir))
        block = f'''
{MARKER_BEGIN}
# Added by install-clang-mg.py
if test -d "{escaped}"
    if not contains "{escaped}" $PATH
        set -gx PATH "{escaped}" $PATH
    end
end
{MARKER_END}
'''
    elif extension == ".ps1" or name in {"powershell", "pwsh"}:
        escaped = escape_ps_single(str(bin_dir))
        block = f'''
{MARKER_BEGIN}
# Added by install-clang-mg.py
$clangMgBinDir = '{escaped}'
if (Test-Path -LiteralPath $clangMgBinDir -PathType Container) {{
    $clangMgPathParts = $env:Path -split [regex]::Escape([System.IO.Path]::PathSeparator)
    if ($clangMgPathParts -notcontains $clangMgBinDir) {{
        $env:Path = "$clangMgBinDir$([System.IO.Path]::PathSeparator)$env:Path"
    }}
}}
{MARKER_END}
'''
    else:
        escaped = escape_sh_double(str(bin_dir))
        block = f'''
{MARKER_BEGIN}
# Added by install-clang-mg.py
if [ -d "{escaped}" ]; then
    case ":$PATH:" in
        *":{escaped}:"*) ;;
        *) export PATH="{escaped}:$PATH" ;;
    esac
fi
{MARKER_END}
'''
    with file_path.open("a", encoding="utf-8") as f:
        f.write(block)


def main(argv: list[str]) -> int:
    help_requested = False
    input_path = ""
    for arg in argv:
        if arg in {"-h", "--help"}:
            help_requested = True
        elif not input_path:
            input_path = arg
        else:
            print(f"ERROR: Unknown extra argument: {arg}")
            return 1

    root_dir = root_from_script(__file__)
    clang_suffix = env_or_default("CLANG_SUFFIX", "mg")
    work_dir = Path(env_or_default("WORK_DIR", root_dir / "work"))
    build_dir = Path(env_or_default("BUILD_DIR", work_dir / "build"))
    profile_file_env = os.environ.get("PROFILE_FILE", "")
    path_scope = env_or_default("CLANG_MG_PATH_SCOPE", "Auto")
    exe_base_name = f"clang-{clang_suffix}"
    script_path = Path(__file__).resolve()

    if help_requested:
        show_usage(build_dir, path_scope)
        return 0

    exe_path = resolve_clang_exe_path(input_path, build_dir, exe_base_name)
    if not exe_path.is_file() or (not is_windows() and not os.access(exe_path, os.X_OK)):
        print(f"ERROR: Could not find executable {exe_base_name}:")
        print(f"  {exe_path}")
        print()
        print("Build clang-mg first, or pass the executable/build directory:")
        print(f"  scripts/install-clang-mg.py work/build/bin/{exe_base_name}")
        print("  scripts/install-clang-mg.py work/build")
        return 1

    exe_path = resolve_full_path_loose(exe_path)
    bin_dir = resolve_full_path_loose(exe_path.parent)
    resolved_input_path = exe_path if not input_path.strip() else resolve_full_path_loose(input_path)

    print("=== install clang-mg ===")
    print(f"Executable:   {exe_path}")
    print(f"Binary dir:   {bin_dir}")

    profile_file: Path | None = None
    if is_windows() and not profile_file_env.strip():
        print(f"PATH target:  Windows {path_scope} PATH")
        print(f"Admin:        {'yes' if is_admin() else 'no'}")
    else:
        profile_file = resolve_full_path_loose(profile_file_env) if profile_file_env.strip() else detected_shell_profile()
        profile_file = resolve_full_path_loose(profile_file)
        print(f"Profile file: {profile_file}")

    print()
    print("Checking clang-mg...")
    cp = run([str(exe_path), "--version"], check=False)
    if cp.returncode != 0:
        print(f"WARNING: Could not run '{exe_path} --version'. Continuing anyway.")

    if is_windows() and not profile_file_env.strip():
        print()
        print("Updating Windows PATH...")
        add_windows_persistent_path(bin_dir, resolved_input_path, path_scope, script_path, exe_base_name, clang_suffix, build_dir)
        print()
        print("Install complete.")
        print()
        print("Open a brand-new cmd.exe or Windows Terminal tab.")
        print("Do not test from a cmd.exe that launched this PowerShell; parent terminals cannot inherit child-process environment changes.")
        print()
        print("Then check:")
        print(f"  where {exe_base_name}")
        print(f"  {exe_base_name} --version")
        print()
        print("Persistent User PATH check:")
        print(f"  powershell -NoProfile -Command \"[Environment]::GetEnvironmentVariable('Path','User') -split ';' | Select-String -SimpleMatch '{bin_dir}'\"")
        print()
        print("Persistent Machine PATH check:")
        print(f"  powershell -NoProfile -Command \"[Environment]::GetEnvironmentVariable('Path','Machine') -split ';' | Select-String -SimpleMatch '{bin_dir}'\"")
        return 0

    assert profile_file is not None
    profile_file.parent.mkdir(parents=True, exist_ok=True)
    profile_file.touch(exist_ok=True)

    print()
    print("Removing old clang-mg PATH block if present...")
    remove_old_blocks(profile_file)
    print("Adding updated clang-mg PATH block...")
    add_profile_path_block(profile_file, bin_dir)
    add_dir_to_current_process_path(bin_dir)

    print()
    print("Installed clang-mg PATH entry.")
    print()
    print("Open a new terminal, or run one of these for the current shell:")
    name = shell_name()
    if name == "fish":
        print(f'  set -gx PATH "{bin_dir}" $PATH')
    elif profile_file.suffix.lower() == ".ps1" or name in {"powershell", "pwsh"}:
        print(f'  $env:Path = "{bin_dir}{os.pathsep}$env:Path"')
    else:
        print(f'  export PATH="{bin_dir}:$PATH"')
    print()
    print("Then check:")
    print(f"  {exe_base_name} --version")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
