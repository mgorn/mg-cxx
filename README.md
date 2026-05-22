# C++MG

C++MG is a Clang/LLVM-based C++ compiler project. The goal is to explore language features that make C++ easier to configure, compose, and extend while still keeping the performance, control, and systems-level strengths that make C++ valuable.

The main focus is improving compile-time programming and making certain patterns less awkward, especially cases where modern C++ already has the information it needs but still forces the programmer into verbose workarounds.

Come talk about the project on [Discord](https://discord.gg/RM8BVwAfZy)!

## Project status

C++MG is currently experimental. The syntax, implementation details, feature names, and patch layout may change as the project develops.

Current areas of improvement include:

- `if constexpr` inside class and struct member scopes
- A renamed compiler executable, `clang-mg`
- `#curlinclude` for cached remote header includes
- Traits for structural member checks
- Type expressions for composing and comparing structures

## Features

### `if constexpr` class members

C++ already has `if constexpr` for conditionally compiling code inside functions. C++MG extends that idea to class and struct member declarations.

The motivation is simple: sometimes a type should only contain a member when a compile-time condition is true. Standard C++ usually forces this through helper templates, partial specializations, inheritance tricks, or wrapper types.

For example, in standard C++, a conditional member often ends up looking something like this:

```cpp
template<bool Enabled>
struct CounterStorage {};

template<>
struct CounterStorage<true> {
  int counter = 0;
};

struct B {
  static constexpr bool hasCounter = true;

  CounterStorage<hasCounter> storage;

  void func() {
    if constexpr (hasCounter) {
      storage.counter = 2;
    }
  }
};
```

With C++MG, the intent can be written directly in the class body:

```cpp
struct B {
  static constexpr bool hasCounter = true;

  if constexpr (hasCounter) {
    int counter = 0;
  }

  template<typename T = B>
  void func(T& value) {
    if constexpr (T::hasCounter) {
      value.counter = 2;
    }
  }
};
```

The member only exists when the condition is true:

```cpp
struct WithCounter {
  static constexpr bool hasCounter = true;

  if constexpr (hasCounter) {
    int counter = 0;
  }
};

struct WithoutCounter {
  static constexpr bool hasCounter = false;

  if constexpr (hasCounter) {
    int counter = 0;
  }
};

static_assert(WithCounter::hasCounter);
static_assert(!WithoutCounter::hasCounter);
```

When using conditional members, any code that accesses those members should also be guarded by a compile-time check. Otherwise, the compiler may still try to semantically analyze code that refers to a member that does not exist for a given type.

Feature detection is available through the `__cxxmg_if_constexpr_member` macro:

```cpp
#ifdef __cxxmg_if_constexpr_member
struct Example {
  static constexpr bool enabled = true;

  if constexpr (enabled) {
    int value = 0;
  }
};
#endif
```

You can also use Clang-style feature detection:

```cpp
#if __has_feature(cxxmg_if_constexpr_members)
// C++MG conditional class members are available.
#endif
```

### Renamed executable: `clang-mg`

The compiler executable is named `clang-mg` instead of `clang`.

This keeps C++MG separate from a normal Clang installation, making it easier to install, test, and use both compilers on the same system without conflicts.

Example:

```bash
clang-mg main.cpp -o app
```

### `#curlinclude`

C++MG adds a `#curlinclude` directive for downloading a remote header, caching it locally, and including it like a normal header.

Example:

```cpp
#curlinclude "https://example.com/some/header.hpp"

int main() {
  return 0;
}
```

Downloaded files are cached in the `.cxxmg/` directory so the same header does not need to be downloaded repeatedly.

This feature is useful for experiments, small projects, examples, and quick dependency tests. For production code, remote includes should be used carefully because they introduce security, reproducibility, and availability concerns. Prefer pinned URLs, trusted sources, and committed lockfiles or vendored copies when stability matters.

### Traits

C++MG traits are a lightweight way to describe the structure a type should have. They are intended to be simpler than full C++ concepts when all you need is a structural member check.

A trait looks similar to a `struct` or `class`, but it describes a required shape instead of defining a normal type:

```cpp
struct A {
  int value = 0;
};

struct B {
  bool test = false;
};

trait ValueTrait {
  int value;
};

trait TestTrait {
  bool test;
};
```

Traits can then be used to test whether a type has the required members:

```cpp
static constexpr bool aHasValue = ValueTrait && A;
static constexpr bool bHasTest = TestTrait && B;
```

The goal is to make simple structural checks readable without requiring a larger concepts-based setup.

### Type expressions

Type expressions allow classes, structs, and traits to be combined or compared more directly. The idea is similar to set operations, but applied to type members.

Using the previous `A`, `B`, `ValueTrait`, and `TestTrait` examples:

```cpp
using C = A + B;
```

Conceptually, that produces a type like this:

```cpp
struct C {
  int value = 0;
  bool test = false;
};
```

Traits can also be combined:

```cpp
using CombinedTrait = ValueTrait + TestTrait;
```

Conceptually, that produces a trait like this:

```cpp
trait CombinedTrait {
  int value;
  bool test;
};
```

You can then check whether a type matches part or all of a trait expression:

```cpp
static constexpr bool hasAnyRequiredMember = CombinedTrait || C;
static constexpr bool hasAllRequiredMembers = CombinedTrait && C;
```

The goal is to make structural composition and structural checks easier to express directly in the language.

## Building

Maintaining a full LLVM fork can be difficult because LLVM changes constantly. This repository is organized around patch sets that can be applied to an LLVM checkout to enable individual C++MG features.

A typical workflow is:

1. Clone or update LLVM.
`./build.sh update`
2. Apply the desired C++MG patches.
`./build.sh apply <feature>`
3. Configure & build LLVM/Clang.
`./build.sh build`
4. Install the compiler/add it to PATH
`./build.sh install`
5. Use the resulting `clang-mg` executable to compile test programs.

On Windows, use the PowerShell build script:

```powershell
.\build.ps1 build
```

The exact build command may vary depending on your platform, generator, LLVM checkout location, and enabled features.

## Testing a feature

After building, create a small test file:

```cpp
struct S {
  static constexpr bool enabled = false;

  if constexpr (enabled) {
    int value = 0;
  }
};

int main() {
  S s;
  return 0;
}
```

Compile it with C++MG:

```bash
clang-mg test.cpp -o test
```

To verify that disabled conditional members are not available, this should fail when `enabled` is `false`:

```cpp
struct S {
  static constexpr bool enabled = false;

  if constexpr (enabled) {
    int value = 0;
  }
};

int main() {
  S s;
  s.value = 1; // Expected error: value does not exist when enabled is false.
}
```

## Goals

C++MG is meant to answer a practical question:

> What would C++ feel like if some common compile-time patterns were supported directly by the compiler?

The project is especially interested in features that:

- Reduce template boilerplate
- Make compile-time configuration easier to read
- Improve structural programming in C++
- Keep generated code efficient
- Help humans and AI tools work with C++ more effectively

## Contributing

Issues, experiments, bug reports, and feature ideas are welcome.

If you test the compiler and find a case where a feature behaves incorrectly, include:

- The smallest code example that reproduces the issue
- The command used to compile it
- The expected behavior
- The actual behavior
- Your operating system and compiler build details

## License

I'm still deciding on licensing, talk to me if you'd like to use this in production for some reason.