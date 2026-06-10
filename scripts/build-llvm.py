#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from clang_mg_common import (cmd_path, default_jobs, detect_target_triple, has_cmd,
                             is_macos, is_windows, run)


def show_usage(script_name: str) -> None:
    print(f"Usage: {script_name} <llvm-dir> [build-dir] [build-type] [jobs] [--interactive]")
    print()
    print("Examples:")
    print(f"  {script_name} work/llvm-project")
    print(f"  {script_name} work/llvm-project work/build-x86_64-pc-windows-msvc")
    print(f"  {script_name} work/llvm-project work/build-x86_64-pc-windows-msvc Release 8")
    print(f"  {script_name} work/llvm-project work/build-x86_64-pc-windows-msvc Release 8 --interactive")
    print()
    print("Environment variables:")
    print("  BUILD_TARGET_TRIPLE=x86_64-pc-windows-msvc")
    print("  CC=<path-or-name>                 Override C compiler")
    print("  CXX=<path-or-name>                Override C++ compiler")
    print("  ASM=<path-or-name>                Override generic ASM compiler")
    print("  ASM_MASM=<path-or-name>           Override MSVC MASM compiler, usually ml64.exe")
    print("  LLVM_ENABLE_PROJECTS=clang        Semicolon-separated LLVM projects to configure")
    print("  CLANG_MG_GENERATOR=Ninja          Override CMake generator; unset prefers Ninja if available")
    print("  CLANG_MG_DEEP_COMPILER_SEARCH=1   Also search Program Files recursively")
    print("  CLANG_MG_DISABLE_ASSEMBLY_FILES=1 Disable LLVM assembly sources if MASM is unavailable")


def add_directory_to_path(directory: Path) -> None:
    if not directory.is_dir():
        return
    sep = os.pathsep
    target = str(directory.resolve()).rstrip("\\/")
    for part in os.environ.get("PATH", "").split(sep):
        if part and part.rstrip("\\/").lower() == target.lower():
            return
    os.environ["PATH"] = f"{directory}{sep}{os.environ.get('PATH', '')}"


def import_environment_from_batch(batch_file: Path, args: list[str] | None = None) -> bool:
    if not batch_file.is_file() or not is_windows():
        return False
    args = args or []

    # A batch file cannot directly modify this Python process environment. Run it
    # inside one cmd.exe process, dump that process environment with `set`, then
    # import the variables back into os.environ. Use `call` so the command after
    # the batch file always runs even when the batch file exits normally.
    cmd_line = 'call "' + str(batch_file) + '"'
    if args:
        cmd_line += " " + " ".join(args)
    cmd_line += " >nul && set"

    cp = subprocess.run(["cmd.exe", "/d", "/s", "/c", cmd_line], stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True)
    if cp.returncode != 0:
        if cp.stderr.strip():
            print(cp.stderr.strip())
        return False
    for line in cp.stdout.splitlines():
        if "=" not in line:
            continue
        name, value = line.split("=", 1)
        if name:
            os.environ[name] = value
    return True


def find_vswhere() -> Path | None:
    p = cmd_path("vswhere.exe")
    if p:
        return Path(p)
    pf86 = os.environ.get("ProgramFiles(x86)", "")
    if pf86:
        candidate = Path(pf86) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
        if candidate.is_file():
            return candidate
    return None


def get_visual_studio_installations() -> list[Path]:
    vswhere = find_vswhere()
    if not vswhere:
        return []
    cp = subprocess.run([str(vswhere), "-products", "*", "-requires",
                         "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
                         "-property", "installationPath"], stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, text=True)
    if cp.returncode != 0:
        return []
    return [Path(line.strip()) for line in cp.stdout.splitlines() if line.strip()]


def import_visual_studio_environment() -> bool:
    if not is_windows():
        return False
    if os.environ.get("VSCMD_VER", "").strip():
        print(f"Visual Studio developer environment already active: {os.environ['VSCMD_VER']}")
        return True
    for installation in get_visual_studio_installations():
        vs_dev_cmd = installation / "Common7" / "Tools" / "VsDevCmd.bat"
        if vs_dev_cmd.is_file():
            print("Loading Visual Studio developer environment:")
            print(f"  {vs_dev_cmd}")
            if import_environment_from_batch(vs_dev_cmd, ["-arch=x64", "-host_arch=x64"]):
                return True
        vcvars64 = installation / "VC" / "Auxiliary" / "Build" / "vcvars64.bat"
        if vcvars64.is_file():
            print("Loading Visual Studio VC environment:")
            print(f"  {vcvars64}")
            if import_environment_from_batch(vcvars64):
                return True
    return False


def add_dir_if_present(dirs: list[Path], directory: str | Path | None) -> None:
    if not directory:
        return
    p = Path(directory)
    if p.is_dir() and p not in dirs:
        dirs.append(p)


def known_compiler_search_directories() -> list[Path]:
    dirs: list[Path] = []
    for part in os.environ.get("PATH", "").split(os.pathsep):
        add_dir_if_present(dirs, part)
    if is_windows():
        pf = os.environ.get("ProgramFiles", "")
        pf86 = os.environ.get("ProgramFiles(x86)", "")
        if pf:
            add_dir_if_present(dirs, Path(pf) / "LLVM" / "bin")
        if pf86:
            add_dir_if_present(dirs, Path(pf86) / "LLVM" / "bin")
        for installation in get_visual_studio_installations():
            add_dir_if_present(dirs, installation / "VC" / "Tools" / "Llvm" / "x64" / "bin")
            add_dir_if_present(dirs, installation / "VC" / "Tools" / "Llvm" / "bin")
            msvc_root = installation / "VC" / "Tools" / "MSVC"
            if msvc_root.is_dir():
                for version_dir in sorted([p for p in msvc_root.iterdir() if p.is_dir()], key=lambda p: p.name, reverse=True):
                    add_dir_if_present(dirs, version_dir / "bin" / "Hostx64" / "x64")
                    add_dir_if_present(dirs, version_dir / "bin" / "Hostx64" / "x86")
                    add_dir_if_present(dirs, version_dir / "bin" / "Hostx86" / "x64")
                    add_dir_if_present(dirs, version_dir / "bin" / "Hostx86" / "x86")
        if re.match(r"^(1|true|yes|on)$", os.environ.get("CLANG_MG_DEEP_COMPILER_SEARCH", ""), re.I):
            print("Deep compiler search enabled. Searching Program Files; this may take a bit...")
            for root in (pf, pf86):
                if not root or not Path(root).is_dir():
                    continue
                for name in ("clang-cl.exe", "clang.exe", "clang++.exe", "cl.exe", "ml64.exe"):
                    for p in Path(root).rglob(name):
                        add_dir_if_present(dirs, p.parent)
    # Preserve insertion order while deduping.
    out: list[Path] = []
    seen: set[str] = set()
    for d in dirs:
        key = str(d).lower() if is_windows() else str(d)
        if key not in seen:
            seen.add(key)
            out.append(d)
    return out


def find_executable_in_known_locations(names: list[str]) -> str | None:
    for name in names:
        p = cmd_path(name)
        if p:
            return p
    for directory in known_compiler_search_directories():
        for name in names:
            candidate = directory / name
            if candidate.is_file():
                add_directory_to_path(directory)
                return str(candidate)
    return None


def resolve_compiler_path(value: str | None) -> str | None:
    if not value or not value.strip():
        return None
    p = Path(value)
    if p.is_file():
        return str(p.resolve())
    from_path = cmd_path(value)
    if from_path:
        return from_path
    return value


def env_flag_is_true(name: str) -> bool:
    return re.match(r"^(1|true|yes|on)$", os.environ.get(name, ""), re.I) is not None


def find_masm_compiler() -> str | None:
    if not is_windows():
        return None

    for env_name in ("ASM_MASM", "ML64"):
        resolved = resolve_compiler_path(os.environ.get(env_name, ""))
        if resolved and Path(resolved).is_file():
            return resolved

    return find_executable_in_known_locations(["ml64.exe", "ml64"])


def find_cmake_toolchain() -> dict[str, str | None] | None:
    env_cc = os.environ.get("CC", "")
    env_cxx = os.environ.get("CXX", "")
    env_asm = os.environ.get("ASM", "")

    if is_windows():
        import_visual_studio_environment()
    masm = find_masm_compiler()

    if env_cc.strip() or env_cxx.strip():
        cc = resolve_compiler_path(env_cc)
        cxx = resolve_compiler_path(env_cxx)
        if not cc:
            cc = cxx
        if not cxx:
            cxx = cc
        return {
            "C": cc,
            "CXX": cxx,
            "ASM": resolve_compiler_path(env_asm),
            "ASM_MASM": masm,
            "Name": "environment override",
        }

    if is_windows():
        clang_cl = find_executable_in_known_locations(["clang-cl.exe"])
        if clang_cl:
            return {
                "C": clang_cl,
                "CXX": clang_cl,
                "ASM": clang_cl,
                "ASM_MASM": masm,
                "Name": "Visual Studio clang-cl",
            }
        cl = find_executable_in_known_locations(["cl.exe"])
        if cl:
            return {
                "C": cl,
                "CXX": cl,
                "ASM": cl,
                "ASM_MASM": masm,
                "Name": "Visual Studio MSVC cl",
            }

    clang = find_executable_in_known_locations(["clang.exe", "clang"])
    clangxx = find_executable_in_known_locations(["clang++.exe", "clang++"])
    if clang and clangxx:
        return {"C": clang, "CXX": clangxx, "ASM": clang, "ASM_MASM": None, "Name": "LLVM clang"}

    gcc = find_executable_in_known_locations(["gcc.exe", "gcc", "cc"])
    gxx = find_executable_in_known_locations(["g++.exe", "g++", "c++"])
    if gcc and gxx:
        return {"C": gcc, "CXX": gxx, "ASM": gcc, "ASM_MASM": None, "Name": "GNU compiler"}
    return None


def remove_bad_cmake_compiler_cache(build_dir: Path) -> None:
    cache_file = build_dir / "CMakeCache.txt"
    cmake_files = build_dir / "CMakeFiles"
    if not cache_file.is_file():
        return
    text = cache_file.read_text(encoding="utf-8", errors="replace")
    if re.search(r"CMAKE_(C|CXX|ASM|ASM_MASM)_COMPILER[^=]*=.*-NOTFOUND", text):
        print("Removing failed CMake compiler cache:")
        print(f"  {cache_file}")
        cache_file.unlink(missing_ok=True)
        if cmake_files.is_dir():
            shutil.rmtree(cmake_files)


def prompt_debug_build(interactive: bool, build_type: str) -> str:
    if not interactive:
        return build_type
    if not sys.stdin.isatty():
        print("Interactive mode requested, but stdin is not a terminal. Using Release build.")
        return "Release"
    print()
    answer = input("Build an unoptimized Debug build instead of optimized Release? [y/N]: ")
    if answer in {"y", "Y", "yes", "YES", "Yes"}:
        return "Debug"
    return "Release"


def main(argv: list[str]) -> int:
    script_name = str(Path(__file__))
    positional: list[str] = []
    interactive = False
    for arg in argv:
        if arg == "--interactive":
            interactive = True
        elif arg in {"-h", "--help"}:
            show_usage(script_name)
            return 0
        elif arg.startswith("-"):
            print(f"ERROR: Unknown option: {arg}")
            return 1
        else:
            positional.append(arg)
    if len(positional) > 4:
        print("ERROR: Too many arguments.")
        print()
        show_usage(script_name)
        return 1

    llvm_dir = Path(positional[0]) if len(positional) >= 1 else None
    build_target_triple = detect_target_triple()
    build_dir = Path(positional[1]) if len(positional) >= 2 else None
    build_type = positional[2] if len(positional) >= 3 else "Release"
    jobs = default_jobs()
    if len(positional) >= 4:
        try:
            parsed = int(positional[3])
            if parsed <= 0:
                raise ValueError
            jobs = str(parsed)
        except ValueError:
            print(f"ERROR: Jobs must be a positive integer: {positional[3]}")
            return 1

    if llvm_dir is None:
        print("ERROR: Missing LLVM source directory.")
        print()
        print("Usage:")
        print("  scripts/build-llvm.py <llvm-dir> [build-dir] [build-type] [jobs] [--interactive]")
        return 1

    llvm_source_dir = llvm_dir / "llvm"
    if not llvm_source_dir.is_dir():
        print("ERROR: Could not find LLVM source directory:")
        print(f"  {llvm_source_dir}")
        return 1

    if build_dir is None:
        build_dir = llvm_dir.resolve().parent / f"build-{build_target_triple}"

    build_type = prompt_debug_build(interactive, build_type)

    if not has_cmd("cmake"):
        print("ERROR: CMake was not found.")
        print("Please install CMake and make sure it is available in PATH.")
        return 1

    generator: str | None = None
    generator_override = os.environ.get("CLANG_MG_GENERATOR", "")
    if generator_override.strip():
        generator = generator_override.strip()
    elif has_cmd("ninja") or has_cmd("ninja-build"):
        generator = "Ninja"


    toolchain = find_cmake_toolchain()
    if toolchain is None:
        print("ERROR: No usable C/C++ compiler was found.")
        print()
        print("On Windows, install one of these:")
        print("  - Visual Studio Build Tools with C++ tools and Clang tools")
        print("  - Visual Studio with Desktop development with C++")
        print("  - LLVM for Windows")
        print()
        print("Then either run from Developer PowerShell, or let this script load VsDevCmd automatically.")
        print()
        print("You can also override manually:")
        print('  $env:CC="C:\\path\\to\\clang-cl.exe"')
        print('  $env:CXX="C:\\path\\to\\clang-cl.exe"')
        return 1

    remove_bad_cmake_compiler_cache(build_dir)

    print()
    print("Configuring LLVM build...")
    print(f"LLVM dir:      {llvm_dir}")
    print(f"Target triple: {build_target_triple}")
    print(f"Build dir:     {build_dir}")
    print(f"Build type:    {build_type}")
    llvm_enable_projects = os.environ.get("LLVM_ENABLE_PROJECTS", "clang").strip() or "clang"

    print(f"Jobs:          {jobs}")
    print(f"Generator:     {generator or 'CMake default'}")
    print(f"Projects:      {llvm_enable_projects}")
    print(f"Toolchain:     {toolchain['Name']}")
    print(f"C compiler:    {toolchain['C']}")
    print(f"CXX compiler:  {toolchain['CXX']}")
    if toolchain.get("ASM"):
        print(f"ASM compiler:  {toolchain['ASM']}")
    if toolchain.get("ASM_MASM"):
        print(f"MASM compiler: {toolchain['ASM_MASM']}")
    elif is_windows():
        print("MASM compiler: not found; LLVM assembly files will be disabled")
    print()

    cmake_args = [
        "-S", str(llvm_source_dir),
        "-B", str(build_dir),
        f"-DLLVM_ENABLE_PROJECTS={llvm_enable_projects}",
        f"-DCMAKE_BUILD_TYPE={build_type}",
        "-DLLVM_ENABLE_ASSERTIONS=ON",
        f"-DCMAKE_C_COMPILER={toolchain['C']}",
        f"-DCMAKE_CXX_COMPILER={toolchain['CXX']}",
    ]
    if generator:
        cmake_args.extend(["-G", generator])
    if toolchain.get("ASM"):
        cmake_args.append(f"-DCMAKE_ASM_COMPILER={toolchain['ASM']}")
    if toolchain.get("ASM_MASM"):
        cmake_args.append(f"-DCMAKE_ASM_MASM_COMPILER={toolchain['ASM_MASM']}")
    elif is_windows() or env_flag_is_true("CLANG_MG_DISABLE_ASSEMBLY_FILES"):
        cmake_args.append("-DLLVM_DISABLE_ASSEMBLY_FILES=ON")
    if is_macos():
        cmake_args.append("-DCLANG_USE_XCSELECT=ON")

    run(["cmake", *cmake_args])

    print()
    print("Building clang...")
    run(["cmake", "--build", str(build_dir), "--target", "clang", "--config", build_type, "--parallel", str(jobs)])

    print()
    print("Build complete.")
    candidates = [
        build_dir / "bin" / "clang-mg.exe",
        build_dir / "bin" / "clang-mg",
        build_dir / "bin" / "clang.exe",
        build_dir / "bin" / "clang",
    ]
    for candidate in candidates:
        if candidate.is_file():
            print(f"Built: {candidate}")
            run([str(candidate), "--version"], check=False)
            break
    else:
        print("WARNING: Build finished, but no clang or clang-mg binary was found in:")
        print(f"  {build_dir / 'bin'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
