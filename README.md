# clang-mg / C++MG

**clang-mg** is a patched Clang/LLVM-based compiler for experimenting with **C++MG**, a C++ dialect focused on making compile-time structure easier to express directly in code.

C++MG asks a practical question:

> What would C++ feel like if common compile-time patterns were *better* supported directly by the compiler?

Modern C++ already has powerful compile-time tools: templates, concepts, `constexpr`, `if constexpr`, type traits, partial specialization, and more. C++MG does not try to replace those. It experiments with additional language constructs that make some structural compile-time patterns easier to write, easier to read, and closer to the declarations they affect.

```cpp
template <bool Debug>
struct Entity {
  int id;
  float x;
  float y;

  if constexpr (Debug) {
    const char *debugName;
    int debugFlags;
  }
};
```

When `Debug` is `false`, the debug members do not exist in that specialization.

C++MG is currently experimental. It is intended for prototypes, compiler hacking, language-design exploration, and discussion while the implementation matures. The goal is for `clang-mg` to become a reliable Clang-based compiler that can be used for real projects, but it is not a stable production compiler yet.

- Project repository: [github.com/mgorn/mg-cxx](https://github.com/mgorn/mg-cxx)
- Website: [mwg.codes/clang-mg](https://mwg.codes/clang-mg/)
- Community: [GornCord](https://discord.gg/RM8BVwAfZy)

---

## Watch the video!
[![Watch the video](https://img.youtube.com/vi/9pWgwCoNNbI/maxresdefault.jpg)](https://youtu.be/9pWgwCoNNbI)

---

## Features at a glance

| Feature | Example | Purpose |
| --- | --- | --- |
| Class-scope `if constexpr` | `if constexpr (Debug) { int flags; }` | Conditionally declare fields, methods, aliases, nested types, and other class members. |
| Type expressions | `using C = A + B - DebugInfo;` | Compose or subtract record/trait shapes directly in an alias declaration. |
| `#urlinclude` | `#urlinclude "https://example.com/header.hpp"` | Download, cache, and include remote headers, especially useful for single-header libraries. |
| `use ... from ...` | `use std::string from <string>;` | Use declarations defined in other files/headers without `#include`-ing their content.
| Separate executable | `clang-mg++ main.cpp -o app` | Keep the patched compiler separate from normal upstream Clang. |

---

## Why this exists

Modern C++ is powerful, but advanced compile-time behavior often depends on indirect patterns:

- helper templates
- partial specializations
- preprocessor conditionals
- tag dispatch
- generated code
- duplicate debug/release or platform-specific type definitions
- concepts and detection idioms for relatively simple structural checks

Those tools work, but they can make code harder to read, modify, generate, and verify. C++MG explores features that keep C++'s performance and control while making common compile-time structure easier to write directly.

The larger theme is **structural compile-time programming**:

- conditionally present structure
- required structure
- composed structure
- removed structure

This matters for projects where unused members, APIs, code paths, or dependencies should disappear at compile time instead of being selected with runtime checks.

C++MG is especially interested in use cases such as:

- game engines
- embedded systems
- operating systems
- graphics libraries
- cross-platform applications
- WebAssembly modules
- performance-sensitive applications

It also matters for AI-assisted development. AI coding tools can help generate and maintain software, but C++ becomes harder to inspect when simple intent is hidden behind scattered templates, macros, and specializations. Cleaner compile-time syntax can make generated C++ easier for humans to audit while still compiling down to efficient code.

---

## Project status

C++MG is currently experimental. Syntax, implementation details, diagnostics, feature names, generated AST representation, and patch layout may change as the project develops.

| Area | Current status |
| --- | --- |
| Generalized `if constexpr` | Was (poorly) implemented for class-level, needs redesign. |
| Type expressions | Implemented very poorly. |
| `#urlinclude` | Implemented as a practical remote-include preprocessor extension with caching, offline mode, and tests. |
| `use ... from ...` | Not implemented yet. |
| Tooling and build scripts | Python-based repository workflow around LLVM checkout/build/patch management. |
| Production stability | It doesn't work. (yet) |

This repository is not an official LLVM distribution. If `clang-mg` crashes, report the issue to the C++MG project unless the same crash also reproduces with official upstream Clang.

---

## Quick start

### Requirements

At a minimum, building clang-mg requires the usual LLVM development dependencies for your platform, including:

- Git
- Python 3
- CMake
- Ninja or another supported CMake generator
- a working host C++ compiler toolchain

This repository uses the cross-platform `build.py` entry point for the main workflow.

### Installing Python 3

Most developers working on a compiler project will already have Python 3 installed. If not, install it using the normal package manager for your platform.

```bash
# Debian / Ubuntu
sudo apt install python3

# Fedora
sudo dnf install python3

# Arch Linux
sudo pacman -S python

# macOS with Homebrew
brew install python
```

On Windows, install Python 3 from the Python website, the Microsoft Store, or `winget`:

```powershell
winget install Python.Python.3
```

On Unix-like systems the command is usually `python3`. On Windows, the Python launcher command is usually `py -3`.

### Build clang-mg

```bash
git clone https://github.com/mgorn/mg-cxx.git
cd mg-cxx

# Clone/update LLVM, apply the C++MG patch stack, configure, and build.
python3 build.py bootstrap

# Patch, build & install clang-mg.
python3 build.py install

# (Optional) Run the C++MG Clang tests.
python3 build.py test clang cxxmg
```

On Windows, use the same script through the Python launcher:

```powershell
git clone https://github.com/mgorn/mg-cxx.git
cd mg-cxx

py -3 build.py bootstrap
py -3 build.py install
py -3 build.py test clang cxxmg
```

After building, compile programs with `clang-mg++`:

```bash
clang-mg++ main.cpp -o app
```

`clang-mg++` defaults to the latest supported C++ standard, so the basic examples do not need a `-std=` flag.

---

## Build workflow

The repository is organized around applying C++MG patches to an LLVM checkout under `work/`.

Common commands:

```bash
# Show available commands and options.
python3 build.py --help

# Clone the LLVM checkout if needed.
python3 build.py clone

# Update the LLVM checkout.
python3 build.py update

# Reset the LLVM checkout back to the configured upstream ref.
python3 build.py reset

# Apply the C++MG patch stack from patches/.
python3 build.py apply

# Configure/build the compiler.
python3 build.py build

# Reset the LLVM checkout, apply paches, and build fresh. (Same as 'rebuild' command)
python3 build.py fresh

# Run tests.
python3 build.py test clang cxxmg

# Install or expose clang-mg.
python3 build.py install
```

Patch-maintenance commands:

```bash
# Refresh patch files from the current LLVM checkout changes.
python3 build.py refresh

# Save current changes into the patch workflow.
python3 build.py save

# Export the net effect of the applied C++MG patch stack into work/.
python3 build.py export
```

The export command is useful for review, debugging, and inspecting only the C++MG changes on top of LLVM while keeping the individual patch files in `patches/` intact.

---

## Language mode and feature detection

C++MG language extensions are controlled by the `-fcxxmg` / `-fno-cxxmg` option pair.

```bash
clang-mg++ -fcxxmg main.cpp -o app
clang-mg++ -fno-cxxmg main.cpp -o app
```

The patched compiler currently enables C++MG language extensions by default. Passing `-fno-cxxmg` disables C++MG syntax such as generalized `if constexpr`, and type expressions.

Clang-style feature detection is available:

```cpp
#if __has_feature(cxxmg_generalized_if_constexpr)
// generalized if constexpr is available
#endif

#if __has_feature(cxxmg_type_expressions)
// type expressions are available
#endif

#if __has_feature(cxxmg_use_from)
// use ... from ... syntax is available
#endif

#if __has_feature(cxxmg_urlinclude)
// #urlinclude is available
#endif
```

C++MG also defines feature-test macros while C++MG language mode is enabled:

```cpp
#ifdef __cxxmg_generalized_if_constexpr
#endif

#ifdef __cxxmg_type_expressions
#endif

#ifdef __cxxmg_use_from
#endif
```

`#urlinclude` is controlled separately by `-furlinclude` / `-fno-urlinclude`, and exposes its own feature macro:

```cpp
#ifdef __cxxmg_urlinclude
#endif
```

---

## Feature Spec

For full specifications and info on C++MG features, see the `docs/` folder.

- [Generalized `if constexpr` spec](docs/cxxmg-generalized-if-constexpr-spec.md)
- Type expressions spec (WIP)
- [`use ... fron ...` spec](docs/cxxmg-use-from-spec.md)
- `#urlinclude` spec (WIP)

---

## Testing C++MG features

The C++MG tests live under the LLVM test tree after patches are applied, primarily in:

```text
clang/test/CXXMG/
```

Feature-specific tests are organized into subdirectories such as:

```text
clang/test/CXXMG/conditional-members/ (deprecated)
clang/test/CXXMG/generalized-if-constexpr/
clang/test/CXXMG/traits/ (deprecated)
clang/test/CXXMG/type-expressions/
clang/test/CXXMG/urlinclude/
clang/test/CXXMG/usefrom/
```

Run the C++MG Clang tests with:

```bash
python3 build.py test clang cxxmg
```

---

## Patch-based workflow

C++MG is maintained as patches on top of LLVM rather than as a permanently diverged copy of every LLVM source file.

This makes it easier to:

- see which files C++MG changes
- update against newer LLVM revisions
- review experimental features independently
- reset and reapply the patch stack
- remove or reorganize features as the design changes

The normal workflow is:

```bash
python3 build.py reset
python3 build.py apply
python3 build.py build
```

Use `python3 build.py --help` for the authoritative command list supported by your local checkout.

---

## Contributing

Issues, experiments, bug reports, test cases, and feature ideas are welcome.

If you find a case where a C++MG feature behaves incorrectly, please include:

- the smallest code example that reproduces the issue
- the command used to compile it
- the expected behavior
- the actual behavior
- your operating system
- the LLVM revision or C++MG checkout revision used
- any relevant crash reproducer files

If `clang-mg` crashes, report it only to the [C++MG issue tracker](https://github.com/mgorn/mg-cxx/issues). Do **not** report clang-mg crashes to the LLVM project. They will probably get upset with you. (And rightfully so!)

---

## License

Licensing for C++MG patch-owned source files and project-specific code is still being decided.

Do not treat this project as production-ready or redistribution-ready until the license situation is finalized.

Licensing suggestions are welcome!