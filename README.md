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

## Features at a glance

| Feature | Example | Purpose |
| --- | --- | --- |
| Class-scope `if constexpr` | `if constexpr (Debug) { int flags; }` | Conditionally declare fields, methods, aliases, nested types, and other class members. |
| Traits | `trait Drawable { void draw(); };` | Describe the required structure of a type without defining an object type. |
| `implements` expressions | `static_assert(T implements Drawable);` | Check structural requirements at compile time. |
| Type expressions | `using C = A + B - DebugInfo;` | Compose or subtract record/trait shapes directly in an alias declaration. |
| `#urlinclude` | `#urlinclude "https://example.com/header.hpp"` | Download, cache, and include remote headers, especially useful for single-header libraries. |
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
- compiler tooling
- performance-sensitive libraries

It also matters for AI-assisted development. AI coding tools can help generate and maintain software, but C++ becomes harder to inspect when simple intent is hidden behind scattered templates, macros, and specializations. Cleaner compile-time syntax can make generated C++ easier for humans to audit while still compiling down to efficient code.

---

## Project status

C++MG is currently experimental. Syntax, implementation details, diagnostics, feature names, generated AST representation, and patch layout may change as the project develops.

| Area | Current status |
| --- | --- |
| Class-scope `if constexpr` | Implemented as a C++MG language extension with tests. |
| Traits and `implements` | Implemented as structural requirement checks with tests. |
| Type expressions | Implemented for record/trait shape composition and subtraction with tests. |
| `#urlinclude` | Implemented as a practical remote-include preprocessor extension with caching, offline mode, and tests. |
| Tooling and build scripts | Python-based repository workflow around LLVM checkout/build/patch management. |
| Production stability | Not currently guaranteed while the compiler is still experimental. Stable builds are a future goal. |

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

# Install or expose the resulting clang-mg executable.
python3 build.py install

# Run the C++MG Clang tests.
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

The patched compiler currently enables C++MG language extensions by default. Passing `-fno-cxxmg` disables C++MG syntax such as `trait`, `implements`, class-scope `if constexpr`, and type expressions.

Clang-style feature detection is available:

```cpp
#if __has_feature(cxxmg_if_constexpr_members)
// class-scope if constexpr is available
#endif

#if __has_feature(cxxmg_traits)
// trait and implements support is available
#endif

#if __has_feature(cxxmg_type_expressions)
// type expressions are available
#endif
```

C++MG also defines feature-test macros while C++MG language mode is enabled:

```cpp
#ifdef __cxxmg_if_constexpr_member
#endif

#ifdef __cxxmg_traits
#endif

#ifdef __cxxmg_type_expressions
#endif
```

`#urlinclude` is controlled separately by `-furlinclude` / `-fno-urlinclude`, and exposes its own feature macro:

```cpp
#ifdef __cxxmg_urlinclude
#endif
```

---

## Class-scope `if constexpr`

Standard C++ does not allow declarations to be selected directly inside a class body with `if constexpr`. Conditional structure is usually modeled through helper templates, partial specializations, inheritance, or preprocessor macros.

C++MG allows `if constexpr` declarations at class scope:

```cpp
template <bool ThreadSafe>
struct Counter {
  int value = 0;

  if constexpr (ThreadSafe) {
    mutable Mutex mutex;
  }

  void increment() {
    if constexpr (ThreadSafe) {
      Lock lock(mutex);
      ++value;
    } else {
      ++value;
    }
  }
};
```

The selected members become real members of the class specialization. Members from inactive arms do not exist in that specialization.

Conditional member chains support `if constexpr`, `else if constexpr`, and final `else` arms:

```cpp
template <int Mode>
struct Storage {
  if constexpr (Mode == 0) {
    int small;
  } else if constexpr (Mode == 1) {
    long medium;
  } else {
    long long large;
  }
};
```

Conditional arms can contain many kinds of class members, including:

```cpp
template <bool Enabled>
struct Example {
  if constexpr (Enabled) {
    int field;
    static int staticField;

    using value_type = int;

    struct Nested {
      int value;
    };

    enum Kind { A, B };

    void method();
    static void staticMethod();
  }
};
```

### Access control

Access specifiers apply around conditional members the same way they apply around ordinary members:

```cpp
class AccessExample {
public:
  if constexpr (true) {
    int visible;
  }

private:
  if constexpr (true) {
    int hidden;
  }
};
```

Access specifiers are intentionally not part of the conditional member body. Put `public:`, `private:`, or `protected:` before or after the conditional declaration, not inside it.

### Using conditional members

Because a conditional member may not exist for every specialization, member uses should be guarded by the same compile-time condition when the member is not guaranteed to exist.

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags = 0;
  }

  void clearDebugFlags() {
    if constexpr (Debug) {
      debugFlags = 0;
    }
  }
};
```

This mirrors the feature's core rule: inactive members are not present. Code that uses optional structure should prove, at compile time, that the structure exists.

### Non-template use

Class-scope `if constexpr` also works for non-dependent conditions:

```cpp
struct ReleaseOnly {
  static constexpr bool Debug = false;

  if constexpr (Debug) {
    int debugOnly;
  }

  int alwaysPresent;
};
```

Here, `debugOnly` is not a member of `ReleaseOnly`.

---

## Traits and `implements`

C++MG traits describe the required shape of a type. A trait is a requirement shape, not an object type.

```cpp
trait Drawable {
  void draw();
};

struct Sprite {
  void draw();
};

static_assert(Sprite implements Drawable);
```

Traits can describe several kinds of requirements:

```cpp
trait Backend {
  using config_type;       // associated type with any concrete type
  using result_type = int; // associated type that must be exactly int

  int value;               // non-static data member requirement
  static int version;      // static data member requirement

  void generate();         // member function requirement
  void generate() const;   // cv-qualified member function requirement

  static create();         // static function requirement with any return type
};
```

`implements` produces a compile-time boolean expression:

```cpp
trait HasValue {
  int value;
};

struct WithValue {
  int value;
};

struct Empty {};

static_assert(WithValue implements HasValue);
static_assert(!(Empty implements HasValue));
```

The right-hand side of `implements` must be a trait or a type expression that describes requirements. The left-hand side must be a struct, class, or compatible type expression. Unions and incomplete operands are rejected.

Traits are intentionally limited to declarations that describe required structure. They cannot be used as normal object types:

```cpp
trait Shape {
  int value;
};

// Not valid: traits are requirement shapes, not object types.
// Shape s;
// sizeof(Shape);
```

Trait declarations also do not support base clauses, access specifiers, member initializers, function bodies, or special member requirements such as constructors and destructors.

---

## Type expressions

Type expressions let records and traits be composed or subtracted with structural operators.

```cpp
struct Position {
  float x;
  float y;
};

struct Velocity {
  float dx;
  float dy;
};

using MovingEntity = Position + Velocity;

static_assert(__is_same(decltype(MovingEntity{}.x), float));
static_assert(__is_same(decltype(MovingEntity{}.dx), float));
```

A type-expression alias names the generated structural result. Conceptually, the example above behaves like a generated record with the members of both `Position` and `Velocity`.

Subtraction removes matching structure:

```cpp
struct DebugInfo {
  const char *debugName;
  int debugFlags;
};

using DebugEntity = Position + Velocity + DebugInfo;
using ReleaseEntity = DebugEntity - DebugInfo;
```

Traits can also participate in type expressions:

```cpp
trait HasPosition {
  float x;
  float y;
};

trait HasVelocity {
  float dx;
  float dy;
};

using MovingRequirement = HasPosition + HasVelocity;

static_assert(MovingEntity implements MovingRequirement);
```

Type expressions can be used with alias templates:

```cpp
template <class T>
struct BoxedValue {
  T value;
};

struct WithId {
  int id;
};

template <class T>
using IdentifiedValue = BoxedValue<T> + WithId;

static_assert(__is_same(decltype(IdentifiedValue<float>{}.value), float));
static_assert(__is_same(decltype(IdentifiedValue<float>{}.id), int));
```

Conflicting same-name members are diagnosed instead of silently merged:

```cpp
struct A {
  int value;
};

struct B {
  float value;
};

// Error: conflicting generated member named value.
// using Bad = A + B;
```

Special members such as constructors and destructors are not copied as ordinary structural members. Unions and incomplete operands are rejected.

---

## `#urlinclude`

C++MG adds a `#urlinclude` directive for downloading a remote header, caching it locally, and including it like a normal header.

```cpp
#urlinclude "https://example.com/some/header.hpp"

int main() {
  return 0;
}
```

Both quote and angle forms are supported and use the same cache entry:

```cpp
#urlinclude "https://example.com/some/header.hpp"
#urlinclude <https://example.com/some/header.hpp>
```

Downloaded files are cached in `.cxxmg-cache/` by default so the same header does not need to be downloaded repeatedly. The compiler can use `curl`, `wget`, or a configured downloader.

Useful options:

| Option | Meaning |
| --- | --- |
| `-furlinclude` / `-fno-urlinclude` | Enable or disable `#urlinclude`. |
| `-furlinclude-cache-dir=<path>` | Choose the cache directory. |
| `-furlinclude-tool=<tool>` | Choose `curl`, `wget`, or a custom downloader. |
| `-furlinclude-tool-arg=<arg>` | Pass an extra argument to a custom downloader. |
| `-furlinclude-timeout=<seconds>` | Set the download timeout. |
| `-furlinclude-offline` | Use only cached URL headers. |
| `-furlinclude-refresh` | Re-download URL headers and update the cache after successful downloads. |
| `-furlinclude-progress=auto\|always\|never` | Control downloader progress output. |
| `-furlinclude-allow-http` | Permit insecure `http://` URLs. |

Feature detection:

```cpp
#ifdef __cxxmg_urlinclude
#urlinclude "https://example.com/some/header.hpp"
#endif
```

Remote includes are useful for single-header libraries, examples, small projects, quick dependency tests, and reproducible cached dependency workflows. Like any network-based dependency mechanism, they should still be used carefully: remote URLs can create security, reproducibility, and availability risks if they are not pinned, cached, or otherwise controlled.

Prefer trusted URLs, pinned content, offline cache use, committed lockfiles, or vendored copies when stability matters.

A safer CI pattern is to populate the cache once, then build in offline mode:

```bash
clang-mg++ -furlinclude-offline main.cpp -o app
```

---

## Testing C++MG features

The C++MG tests live under the LLVM test tree after patches are applied, primarily in:

```text
clang/test/CXXMG/
```

Feature-specific tests are organized into subdirectories such as:

```text
clang/test/CXXMG/conditional-members/
clang/test/CXXMG/traits/
clang/test/CXXMG/type-expressions/
clang/test/CXXMG/urlinclude/
```

Run the C++MG Clang tests with:

```bash
python3 build.py test clang cxxmg
```

For quick manual testing, create a file like this:

```cpp
trait HasValue {
  int value;
};

struct S {
  static constexpr bool Enabled = true;

  if constexpr (Enabled) {
    int value;
  }
};

static_assert(S implements HasValue);

int main() {
  S s;
  s.value = 1;
}
```

Then compile it with:

```bash
clang-mg++ test.cpp -o test
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

## Current limitations and design rules

C++MG is currently experimental, but not every restriction is a temporary limitation. Some restrictions are intentional design rules.

For conditional members:

- `if constexpr` conditions are compile-time conditions by design.
- Inactive conditional arms are still parsed, so the code must be syntactically valid C++MG.
- Members from inactive arms do not exist.
- Code that uses a conditional member should guard that use when the member is not guaranteed to exist.
- Access specifiers belong around conditional declarations, not inside conditional member bodies.

For traits:

- Traits are requirement shapes, not object types.
- Trait requirements are declarations, not definitions with behavior.
- Trait declarations do not support base clauses, access specifiers, member initializers, function bodies, or special member requirements.

For type expressions:

- Type expressions currently focus on structural composition and subtraction of records/traits.
- Conflicting generated members are diagnosed.
- Special members are not copied as normal structural members.
- Unions and incomplete operands are rejected.

For `#urlinclude`:

- HTTPS is the default supported scheme.
- Insecure HTTP requires `-furlinclude-allow-http`.
- Offline mode requires the requested URL to already be present in the cache.
- Remote includes are a practical dependency mechanism for URL-addressable headers, especially single-header libraries, but they should still be used deliberately with caching, trusted sources, and offline/reproducible workflows where appropriate.

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