# C++MG `use ... from ...` Specification

## 1. Overview

C++MG adds a selective declaration import feature called **use-from**.

A use-from declaration grants source visibility to selected declarations from a header within the current context, without textually including the entire header into that context and without leaking macros or preprocessor state from the used header.

Example:

```cpp
use std::string from <string>;

struct User {
  std::string name;
};
```

Unlike `#include <string>`, this exposes only `std::string` to the current source context. Other declarations and macros from `<string>` are not made generally visible.

The core rule is:

> `use ... from ...` grants source visibility to selected declarations from a header in the current context. The imported header is preprocessed under the current preprocessing state, but macro/preprocessor mutations from the imported header do not leak back. Only the requested declarations and whatever dependency closure is necessary to make them usable need to be semantically valid. Non-selected declarations should not become source-visible, and ideally should not exist at all outside dependency resolution.

## 2. Motivation

Traditional C++ header inclusion is textual and broad:

```cpp
#include <string>
```

This makes all declarations, macros, and preprocessor side effects from the header visible to the including translation unit.

C++MG use-from provides narrower source visibility:

```cpp
use std::string from <string>;
```

This makes `std::string` available where requested, while keeping unrelated declarations and macros from `<string>` out of the local source context.

This enables public headers to depend on implementation types without exposing those dependencies to includers:

```cpp
// user.hxx
struct User {
  use std::string from <string>;

  std::string name;
};
```

A file that includes `user.hxx` may use `User`, but it cannot name `std::string` unless it separately includes or uses it.

## 3. Feature availability

Use-from is a C++MG language feature.

It is enabled in C++MG mode by default.

Implementations may provide switches to explicitly enable or disable it. For clang-mg, the intended flags are:

```bash
-fcxxmg-use-from
-fno-cxxmg-use-from
```

These flag names are implementation-specific and are not part of the portable C++MG language grammar.

## 4. Contextual keywords

`use` and `from` are contextual keywords.

They have special meaning only in a syntactic position where a use-from declaration or use-from expression can be parsed.

Existing code using `use` or `from` as identifiers remains valid:

```cpp
int use = 0;
int from = 1;

void f(int use, int from);
```

The following is parsed as a use-from declaration only because it matches the feature grammar:

```cpp
use ns::Type from <header.hxx>;
```

## 5. Terminology

Use-from defines three declaration categories.

### 5.1 Visible declarations

A **visible declaration** is a declaration directly selected by a `use ... from ...` declaration.

Visible declarations are source-nameable in the context where the use-from declaration applies.

Example:

```cpp
use ns::Type from <header.hxx>;

ns::Type value; // valid
```

### 5.2 Reachable declarations

A **reachable declaration** is a declaration needed to make a visible declaration usable.

Reachable declarations may be needed for layout, member access, template instantiation, overload resolution, ADL, default arguments, inline member function bodies, code generation, or ABI correctness.

Reachable declarations are not directly source-nameable unless separately made visible.

Example:

```cpp
// header.hxx
namespace ns {
  struct Dependency {};

  struct Type {
    Dependency dep;
  };
}
```

```cpp
use ns::Type from <header.hxx>;

ns::Type value;       // valid
ns::Dependency dep;   // invalid unless separately used
```

`ns::Dependency` is reachable because `ns::Type` requires it, but it is not visible.

### 5.3 Ignored declarations

An **ignored declaration** is a declaration from the used header that is unrelated to the requested declarations and their dependency closure.

Ignored declarations are not source-visible and do not need to be semantically validated.

Implementations may still diagnose ignored declarations if their parsing strategy requires it, but the language model does not require unrelated declarations to be valid.

Example:

```cpp
// header.hxx
struct Requested {};

struct Broken {
  MissingType value;
};
```

```cpp
use Requested from <header.hxx>;

Requested r; // valid in the language model
```

`Broken` is unrelated and may be ignored.

## 6. Declaration syntax

A use-from declaration has one of the following forms:

```cpp
use declaration-target from header-name;
use declaration-target-list from header-name;
use { declaration-target-list } from header-name;
use wildcard-target from header-name;
```

Examples:

```cpp
use ns::Type from <header.hxx>;

use ns::A, ns::B, ns::foo from <header.hxx>;

use { ns::A, ns::B, ns::foo } from <header.hxx>;

use ns::* from <header.hxx>;

use * from <header.hxx>;
```

A declaration-form `use` statement always ends with a semicolon:

```cpp
use std::string from <string>;
```

## 7. Header names

The `from` clause accepts the same header-name forms accepted by C++MG include-like features.

Examples:

```cpp
use ns::Type from <header.hxx>;
use ns::Type from "header.hxx";
```

If C++MG URL include support is enabled, use-from may also use URL header locators accepted by the implementation:

```cpp
use ns::Type from <https://example.com/type.hxx>;
```

For URL-backed headers, the implementation should use the same fetching and caching behavior as the corresponding C++MG URL include feature up to the point where the file is ready to be parsed. The difference is that use-from exposes only selected declarations rather than including the entire file.

## 8. Declaration form semantics

A declaration-form use grants visibility starting at the point of declaration.

```cpp
std::string a; // invalid

use std::string from <string>;

std::string b; // valid
```

This ordering rule applies at namespace scope, class scope, block scope, and nested control-flow scopes.

Example:

```cpp
void f(bool cond) {
  if (cond) {
    use std::string from <string>;

    std::string s; // valid
  }

  std::string t; // invalid
}
```

Use-from declarations may appear anywhere declarations may appear.

Examples:

```cpp
namespace N {
  use std::string from <string>;

  std::string value;
}
```

```cpp
struct S {
  use std::string from <string>;

  std::string name;
};
```

```cpp
void f() {
  int x = 0;

  use std::string from <string>;

  std::string s;
}
```

## 9. Nested context inheritance

Visible declarations from an enclosing context are visible in nested contexts unless hidden or shadowed by normal language rules.

```cpp
use std::string from <string>;

struct A {
  std::string text; // valid

  struct Inner {
    std::string moreText; // valid
  };
};
```

A use-from declaration inside a nested context grants visibility only inside that nested context and its children.

```cpp
struct A {
  use std::string from <string>;

  std::string text; // valid
};

struct B {
  std::string text; // invalid
};
```

## 10. Expression form

Use-from may appear as an expression.

The expression extent ends at the `from header-name` clause.

Examples:

```cpp
auto x = use ns::value from <header.hxx>;

auto y = (use ns::value from <header.hxx>) + 1;

auto z = f(use ns::value from <header.hxx>);

static_assert((use ns::flag from <header.hxx>) == true);
```

Expression-form use does not create a lasting visibility grant.

```cpp
auto x = use ns::value from <header.hxx>;

auto y = ns::value; // invalid
```

Expression-form use may be used with functions:

```cpp
(use ns::foo from <header.hxx>)(123);

auto p = &(use ns::foo(int) from <header.hxx>);
```

Expression-form use may be used in type-expression positions when the selected declaration is a type:

```cpp
using T = use ns::Type from <header.hxx>;

static_assert(sizeof(use ns::Type from <header.hxx>) > 0);
```

## 11. Type alias form

Use-from may appear on the right-hand side of a type alias declaration when the selected declaration is a type.

```cpp
using Type = use ns::Type from <header.hxx>;
```

This creates a normal C++ type alias named `Type`.

The original qualified declaration does not become visible merely because it was used in the alias expression.

```cpp
using Type = use ns::Type from <header.hxx>;

Type a;     // valid
ns::Type b; // invalid unless separately used
```

The alias preserves the original type identity.

```cpp
using Type = use ns::Type from <header.hxx>;
```

is semantically equivalent to a normal alias to `ns::Type`, except that `ns::Type` is obtained through use-from rather than prior source visibility.

## 12. Companion `alias` feature

Use-from does not require a non-type alias facility.

A future C++MG `alias` feature may allow declarations such as:

```cpp
alias auto value = use ns::value from <header.hxx>;
```

The intended behavior of `alias` would be:

> `alias` declares a local source-level name that refers to an existing declaration rather than creating a new object, function, or type.

This is a companion feature, not a requirement of use-from.

Until such a feature exists, non-type declarations may still be used through declaration-form use:

```cpp
use ns::value from <header.hxx>;

auto x = ns::value;
```

or expression-form use:

```cpp
auto x = use ns::value from <header.hxx>;
```

Namespaces may be aliased using normal namespace alias syntax together with use-from if the implementation supports namespace use expressions:

```cpp
namespace fs = use std::filesystem from <filesystem>;
```

## 13. Qualified and unqualified names

A use-from declaration preserves namespace qualification.

```cpp
use ns::Type from <header.hxx>;

Type a;     // invalid
ns::Type b; // valid
```

The namespace does not “vanish” when a declaration is used from a header.

To use a shorter name, create a normal alias:

```cpp
using Type = use ns::Type from <header.hxx>;

Type a;     // valid
ns::Type b; // invalid unless separately used
```

Unqualified imports are valid for declarations that are actually reachable by unqualified lookup from the used header’s declaration universe.

```cpp
use Type from <header.hxx>;

Type value;
```

If `Type` is declared inside `ns`, the unqualified form is invalid:

```cpp
use Type from <header.hxx>; // invalid if only ns::Type exists
```

The qualified form must be used:

```cpp
use ns::Type from <header.hxx>;
```

## 14. Namespaces

Use-from may expose namespace declarations as needed to make qualified lookup work.

```cpp
use ns::Type from <header.hxx>;

ns::Type value; // valid
```

Only selected declarations inside the namespace become visible.

```cpp
use ns::Type from <header.hxx>;

ns::Type a;  // valid
ns::Other b; // invalid unless separately used
```

A namespace itself may be selected as a use target if supported by the implementation, but using a namespace declaration alone exposes only the namespace declaration, not all of its members.

Wildcard use should be used to expose namespace contents:

```cpp
use ns::* from <header.hxx>;
```

## 15. Wildcard use

Use-from supports wildcard imports.

```cpp
use * from <header.hxx>;
use ns::* from <header.hxx>;
use ns::inner::* from <header.hxx>;
```

### 15.1 `use *`

`use * from <header.hxx>;` grants visibility to every importable declaration from the used header’s declaration universe, except macros and preprocessor side effects.

It is similar in spirit to importing the header’s declarations wholesale, but without sharing the used header’s macro/preprocessor mutations with the current file.

```cpp
use * from <header.hxx>;
```

### 15.2 `use ns::*`

`use ns::* from <header.hxx>;` grants visibility to every importable declaration in `ns` from the used header’s declaration universe.

Wildcard namespace use is recursive for nested namespaces.

```cpp
// header.hxx
namespace ns {
  struct A {};

  namespace inner {
    struct B {};
  }
}
```

```cpp
use ns::* from <header.hxx>;

ns::A a;        // valid
ns::inner::B b; // valid
```

### 15.3 Class members under wildcard use

If a wildcard import makes a class visible, the class’s members are usable through that class as normal.

```cpp
// header.hxx
namespace ns {
  struct A {
    struct Nested {};
    static int value;
  };
}
```

```cpp
use ns::* from <header.hxx>;

ns::A::Nested n;  // valid
ns::A::value = 1; // valid
```

The class members are reachable through `ns::A`. They are not separately treated as independent wildcard import targets for duplicate-use diagnostics.

## 16. Using-declarations and using-directives

A using-declaration inside a wildcarded namespace is included by wildcard use.

```cpp
// header.hxx
namespace other {
  struct X {};
}

namespace ns {
  using other::X;
}
```

```cpp
use ns::* from <header.hxx>;

ns::X x; // valid
```

A using-directive is not treated as declaring names in the namespace for use-from wildcard purposes.

```cpp
// header.hxx
namespace other {
  struct X {};
}

namespace ns {
  using namespace other;
}
```

```cpp
use ns::* from <header.hxx>;

X x;        // invalid
other::X y; // invalid unless separately used
ns::X z;    // invalid
```

The directive may be reachable for semantic resolution inside declarations that depend on it, but it does not cause transitive namespace contents to become visible.

## 17. Anonymous namespaces

Declarations from anonymous namespaces may be used.

```cpp
// header.hxx
namespace {
  struct Hidden {};
}
```

```cpp
use Hidden from <header.hxx>;

Hidden h;   // valid
::Hidden g; // invalid
```

Anonymous namespace imports are visible through unqualified lookup grants. They do not become ordinary global declarations.

If two anonymous namespace declarations with the same visible spelling are used into the same context, they conflict.

```cpp
use Hidden from <a.hxx>;
use Hidden from <b.hxx>; // error if both expose anonymous Hidden
```

Different contexts do not conflict.

```cpp
struct A {
  use Hidden from <a.hxx>;
};

struct B {
  use Hidden from <b.hxx>;
};
```

Anonymous namespaces inside named namespaces are used through the named namespace path.

```cpp
// header.hxx
namespace ns {
  namespace {
    struct Hidden {};
  }
}
```

```cpp
use ns::Hidden from <header.hxx>;

ns::Hidden h; // valid if lookup rules expose it this way
```

## 18. Templates and specializations

Use-from supports templates.

```cpp
use std::vector from <vector>;

std::vector<int> values;
```

Use-from also supports selected template specializations.

```cpp
use std::vector<int> from <vector>;

std::vector<int> a;   // valid
std::vector<float> b; // invalid unless separately used
```

A type alias may name a selected specialization:

```cpp
using IntVector = use std::vector<int> from <vector>;

IntVector a;        // valid
std::vector<int> b; // invalid unless separately used
```

Partial and explicit specializations are resolved according to normal template matching rules.

```cpp
use Box<int*> from <box.hxx>;
```

This imports the selected specialization after applying normal specialization selection. Primary templates, partial specializations, constraints, and other declarations needed to select and use the specialization are reachable but not necessarily visible.

Explicit specializations behave similarly:

```cpp
use Box<int> from <box.hxx>;
```

If `Box<int>` names an explicit specialization, that specialization is the visible imported declaration. The primary template and supporting declarations are reachable as required.

## 19. Function imports

Use-from supports functions.

```cpp
use ns::foo from <header.hxx>;

ns::foo();
```

Qualified names remain qualified:

```cpp
use ns::foo from <header.hxx>;

foo();     // invalid
ns::foo(); // valid
```

## 20. Function overload sets

A broad function import exposes an imported overload set.

```cpp
use ns::foo from <header.hxx>;
```

The name `ns::foo` becomes visible as an imported overload set. Overload resolution sees all viable imported overloads, but only selected overloads are considered semantically used and codegen-relevant.

```cpp
use ns::foo from <header.hxx>;

ns::foo(1);
ns::foo(1.0);
```

## 21. Explicit overload imports

Use-from supports explicit overload selection.

Examples:

```cpp
use ns::foo(int) from <header.hxx>;
use ns::foo(int) -> int from <header.hxx>;
use ns::foo<int> from <header.hxx>;
use ns::foo<int>(int) from <header.hxx>;
```

The return type is optional overload disambiguation.

```cpp
use ns::foo(int) from <header.hxx>;
```

selects an overload by parameter list.

```cpp
use ns::foo(int) -> int from <header.hxx>;
```

selects an overload by parameter list and return type.

Explicit overload matching follows normal C++ function type identity rules as closely as possible, including references, cv-qualification where semantically meaningful, ref-qualifiers for member functions, `noexcept`, and template arguments.

Top-level parameter type normalization follows normal C++ canonical function parameter rules.

## 22. Member function imports

Member functions may be directly used from a header.

```cpp
use ns::Type::method(int) from <header.hxx>;
```

Importing a member function directly makes only that member declaration visible. The containing type is reachable but not source-visible unless separately used.

```cpp
use ns::Type::method(int) from <header.hxx>;

ns::Type obj; // invalid unless ns::Type is separately used
```

This is allowed but rare. Importing the containing class is usually the preferred form:

```cpp
use ns::Type from <header.hxx>;

ns::Type obj;
obj.method(1); // valid if method is a member of imported Type
```

## 23. Class imports

Importing a class, struct, or union imports the whole class declaration.

```cpp
use ns::Type from <header.hxx>;
```

All members of the class are usable through the imported type.

```cpp
ns::Type obj;

obj.method();
ns::Type::Nested nested;
ns::Type::staticMethod();
ns::Type::staticValue;
```

Constructors, destructors, conversion functions, overloaded operators, member functions, nested types, static data members, static member functions, defaulted special members, and defaulted comparisons are part of the imported class declaration.

Base classes are reachable as necessary.

```cpp
use ns::Derived from <header.hxx>;

ns::Derived d;
d.baseFunc(); // valid if inherited from reachable base
ns::Base b;   // invalid unless ns::Base is separately used
```

## 24. ADL behavior

Reachable associated functions and operators from the used header may participate in argument-dependent lookup when they are semantically attached to a visible imported declaration.

They do not become nameable through ordinary qualified or unqualified lookup unless explicitly used.

```cpp
use ns::Type from <header.hxx>;

ns::Type a, b;

a == b;              // valid if operator== is found through use-from ADL
ns::operator==(a,b); // invalid unless operator== is explicitly used
```

Free operators associated with an imported type may participate in ADL.

Ordinary free helper functions are not automatically exposed merely because their namespace is associated.

```cpp
// header.hxx
namespace ns {
  struct Type {};

  bool operator==(Type, Type);
  void helper(Type);
}
```

```cpp
use ns::Type from <header.hxx>;

ns::Type a, b;

a == b;    // valid
helper(a); // invalid unless helper is explicitly used
```

If a local visible overload exists, the local declaration is used according to normal lookup rules. Unused helper functions from the header are not injected into ordinary lookup.

```cpp
use ns::Type from <header.hxx>;

void helper(ns::Type);

ns::Type x;
helper(x); // uses local helper
```

Friend functions declared inside an imported class are reachable for ADL.

```cpp
// header.hxx
namespace ns {
  struct Type {
    friend bool operator==(Type, Type) {
      return true;
    }
  };
}
```

```cpp
use ns::Type from <header.hxx>;

ns::Type a, b;
a == b; // valid
```

## 25. Strict contextual visibility

A declaration must be visible to be named directly in source.

However, declarations reachable through already-visible types may be used through expressions whose types carry those declarations.

Example:

```cpp
struct A {
  use std::string from <string>;

  std::string name;
};

void f(A a) {
  auto n = a.name.size(); // valid
}
```

Outside `A`, `std::string` itself is not directly nameable unless separately used.

```cpp
void f(A a) {
  std::string s; // invalid unless std::string is visible here
}
```

The expression `a.name` has a known type, and its member functions may be used through member access.

## 26. `auto`, `decltype`, and hidden/reachable types

Use-from allows values to carry types that are not directly source-nameable in the current context.

```cpp
struct A {
  use std::string from <string>;

  std::string name;
};

void f(A a) {
  auto x = a.name;             // valid
  decltype(a.name) y;          // valid
  sizeof(a.name);              // valid
  alignof(decltype(a.name));   // valid
  typeid(a.name);              // valid
}
```

A hidden type may be captured with `decltype`.

```cpp
void f(A a) {
  using HiddenString = decltype(a.name);

  HiddenString s; // valid
}
```

This is an intentional escape hatch. It does not make the original spelling `std::string` visible.

## 27. Function signatures exposing used types

A class may use an imported type in a member function signature.

```cpp
struct A {
  use std::string from <string>;

  std::string getName();
};
```

Outside the class:

```cpp
A a;

auto name = a.getName();         // valid
std::string name2 = a.getName(); // invalid unless std::string is visible here
```

The type exists semantically, but its source spelling is not visible outside its use context.

## 28. Class-scope behavior

A class-scope use-from declaration grants visibility inside the class after the use declaration.

```cpp
struct A {
  use std::string from <string>;

  std::string name;
};
```

Plain use-from declarations are not class members for access-control purposes.

Access specifiers do not affect the use declaration itself.

```cpp
struct A {
private:
  use std::string from <string>;

public:
  std::string get(); // valid
};
```

This is invalid:

```cpp
A::std::string s; // invalid
```

The use declaration does not create a member namespace named `std`.

Normal aliases created using use-from are real class members and follow normal access control.

```cpp
struct A {
public:
  using AStr = use std::string from <string>;
};

A::AStr s; // valid
```

```cpp
struct A {
private:
  using AStr = use std::string from <string>;
};

A::AStr s; // invalid, private member alias
```

## 29. Out-of-class member definitions

A class-scope use applies to out-of-class member definitions only after the parser enters the member’s class context.

```cpp
struct A {
  use std::string from <string>;

  std::string get();
};
```

This is invalid unless `std::string` is visible in the enclosing namespace context:

```cpp
std::string A::get() {
  return {};
}
```

This is valid because the trailing return type is looked up in the member context:

```cpp
auto A::get() -> std::string {
  std::string s;
  return s;
}
```

The function body of an out-of-class member definition inherits the member’s class context.

```cpp
auto A::get() -> std::string {
  std::string s; // valid
  return s;
}
```

## 30. Friend declarations

A friend declaration inside a context may use declarations visible in that context.

```cpp
struct A {
  use std::string from <string>;

  friend void f(std::string);
};
```

This does not make `std::string` visible in the enclosing namespace.

```cpp
void f(std::string); // invalid unless std::string is visible here
```

## 31. Preprocessor behavior

The used header is preprocessed under the importer’s current preprocessing state.

```cpp
#define ENABLE_FEATURE
use ns::Type from <header.hxx>;
```

The header sees `ENABLE_FEATURE`.

Macros and preprocessor mutations from the used header do not leak back to the using file.

```cpp
// header.hxx
#define X 1
struct Type {};
```

```cpp
use Type from <header.hxx>;

#ifdef X
#error leaked
#endif
```

The `#error` does not fire because `X` does not leak.

Header-local macro changes are available while processing the used header itself and while resolving the requested declaration’s dependency closure.

## 32. Macro state and import identity

The declaration universe of a used header is determined by:

1. the physical or logical header identity;
2. the preprocessing state at the point of use;
3. applicable implementation-specific header resolution rules.

Using the same header under different preprocessing states may produce different declarations.

If the same source spelling resolves to different declarations under different preprocessing states, those declarations are distinct and may conflict if made visible in overlapping contexts or if they violate identity/ODR-like rules.

Internal-linkage declarations from the same header identity and preprocessing state within one translation unit refer to the same internal-linkage entity, not a fresh entity per use.

```cpp
// header.hxx
static int counter;
```

```cpp
namespace A {
  use counter from <header.hxx>;
}

namespace B {
  use counter from <header.hxx>;
}
```

Both uses refer to the same translation-unit-local `counter` entity, visible from two contexts.

If the same internal-linkage declaration is used from the same header under an incompatible macro state that changes the definition, an implementation should diagnose the conflict or treat the later use as referring to the already-established entity if the macro change has no semantic effect.

```cpp
#define N 1
namespace A {
  use counter from <header.hxx>;
}

#undef N
#define N 2
namespace B {
  use counter from <header.hxx>;
}
```

If `counter`’s definition depends on `N`, this is an error or an ODR-like conflict.

## 33. Include guards and `#pragma once`

Use-from is not textual inclusion.

Include guards and `#pragma once` do not suppress use-from declarations.

They may participate in implementation caching and header identity, but a prior use of a header does not prevent a later use from granting visibility in another context.

```cpp
struct A {
  use std::string from <string>;
};

struct B {
  use std::string from <string>;
};
```

Both declarations are valid. The implementation may reuse semantic results internally.

## 34. Header slicing and skipped diagnostics

Use-from is not required to semantically validate an entire header.

It must validate the requested visible declarations and the reachable declarations required to make them usable.

Unrelated declarations, unrelated top-level `static_assert`s, unrelated malformed declarations, and unrelated initialization side effects may be ignored.

```cpp
// header.hxx
static_assert(false);

struct Requested {};
```

```cpp
use Requested from <header.hxx>;
```

This may compile, because the top-level `static_assert` is unrelated to `Requested`.

However, if a failing declaration is in the dependency closure, the program is invalid.

```cpp
// header.hxx
struct Helper {
  static_assert(false);
};

struct Requested {
  Helper h;
};
```

```cpp
use Requested from <header.hxx>; // error
```

`Helper` is reachable and required by `Requested`.

## 35. Pragmas, attributes, and layout

Pragmas, attributes, and other source constructs that affect a requested declaration or its reachable dependency closure must be honored.

```cpp
#pragma pack(push, 1)
struct Packed {
  char c;
  int i;
};
#pragma pack(pop)
```

```cpp
use Packed from <header.hxx>;

static_assert(sizeof(Packed) == 5);
```

Attributes on imported declarations are preserved.

```cpp
// header.hxx
struct [[nodiscard]] Result {};
```

```cpp
use Result from <header.hxx>;
```

`Result` retains its attributes.

Attributes on the use-from declaration itself are rejected.

```cpp
[[maybe_unused]] use ns::Type from <header.hxx>; // error
```

Diagnostic:

```text
error: attributes cannot be applied to a C++MG use-from declaration
```

## 36. Side-effect declarations and code generation

Unrelated side-effect declarations may be ignored.

```cpp
// header.hxx
inline int unused = compute();

struct Requested {};
```

```cpp
use Requested from <header.hxx>;
```

`unused` does not need to be emitted or initialized.

If a visible declaration depends on a side-effect declaration, that declaration becomes reachable and must be handled correctly.

```cpp
// header.hxx
inline int helper = compute();

struct Requested {
  int x = helper;
};
```

```cpp
use Requested from <header.hxx>;
```

`helper` is reachable and must be semantically/codegen available as needed.

It is not source-visible unless explicitly used.

```cpp
helper = 2; // invalid unless helper is explicitly used
```

## 37. Normal `#include` interaction

Use-from and `#include` may coexist.

```cpp
use ns::Type from <header.hxx>;

#include <header.hxx>
```

The use-from declaration grants selective visibility before the include.

After the include, normal textual inclusion rules apply and all declarations/macros made visible by the include are visible as usual.

```cpp
use ns::Type from <header.hxx>;

ns::Type a;  // valid
ns::Other b; // invalid before include

#include <header.hxx>

ns::Other c; // valid if included header declares it
```

## 38. Conflicts and duplicate use

A duplicate use of the same declaration in the same context is an error.

```cpp
use std::string from <string>;
use std::string from <string>; // error
```

The error applies regardless of how much source appears between the duplicate uses.

```cpp
use std::string from <string>;

struct A {
  std::string s;
};

use std::string from <string>; // error
```

A redundant nested use of a declaration already visible from an enclosing context is a warning.

```cpp
use std::string from <string>;

struct S {
  use std::string from <string>; // warning
};
```

Diagnostic:

```text
warning: redundant use of 'std::string'; declaration is already visible from an enclosing context
```

The nested redundant use does not create a new independent visibility grant. The enclosing use remains the source of visibility.

If two uses resolve to the same canonical declaration through different headers in the same context, the second is a duplicate use error.

```cpp
use ns::Type from <a.hxx>;
use ns::Type from <b.hxx>; // error if same canonical declaration
```

If they resolve to different declarations with the same visible qualified name, this is a conflict.

```cpp
use ns::Type from <a.hxx>;
use ns::Type from <b.hxx>; // error if different declarations
```

## 39. Forward declarations

A use-from declaration may complete an existing compatible forward declaration.

```cpp
namespace ns {
  struct Type;
}

use ns::Type from <header.hxx>;
```

This is valid.

A later compatible forward declaration after a use-from declaration is treated according to normal C++ redeclaration rules.

```cpp
use ns::Type from <header.hxx>;

namespace ns {
  struct Type;
}
```

This is valid if normal C++ would permit the redeclaration.

No special warning is required solely because an import completed a forward declaration.

## 40. Private and protected declarations

Use-from does not bypass normal C++ access control.

Private and protected nested declarations may be used only where normal C++ access rules permit naming them.

```cpp
// header.hxx
namespace ns {
  struct Type {
  private:
    struct Secret {};
  };
}
```

```cpp
using Secret = use ns::Type::Secret from <header.hxx>; // invalid unless access is permitted
```

Use-from does not enforce library API boundaries beyond normal C++ access. Publicly nameable declarations in detail namespaces may be used.

```cpp
use ns::detail::Impl from <header.hxx>; // valid if normally accessible
```

## 41. Constraints and concepts

Use-from declarations are allowed where declarations are normally allowed.

```cpp
use ns::foo from <header.hxx>;

template <typename T>
concept C = requires(T t) {
  ns::foo(t);
};
```

A use-from declaration is not allowed in a grammar context where declarations are not normally allowed.

```cpp
template <typename T>
concept C = requires(T t) {
  use ns::foo from <header.hxx>; // invalid
  ns::foo(t);
};
```

Expression-form use may be used in constraint expressions if it is otherwise grammatically valid.

## 42. Builtins

C++MG provides two feature-query builtins.

### 42.1 `__can_use_from`

```cpp
__can_use_from(declaration-target, header-name)
```

Returns true if a matching `use declaration-target from header-name;` could resolve the declaration under the current preprocessing state and context rules.

It does not require the declaration to already be visible.

Example:

```cpp
#if __can_use_from(ns::Type, <header.hxx>)
use ns::Type from <header.hxx>;
#endif
```

### 42.2 `__has_decl_from`

```cpp
__has_decl_from(declaration-target, header-name)
```

Returns true if the current context already has source visibility to the declaration and that visibility came from the specified header.

Example:

```cpp
#if __has_decl_from(ns::Type, <header.hxx>)
// false before use
#endif

use ns::Type from <header.hxx>;

#if __has_decl_from(ns::Type, <header.hxx>)
// true after use
#endif
```

`__has_decl_from` is a visibility-origin query, not an availability query.

## 43. Diagnostics

Use-from diagnostics should explain whether a declaration is missing, not visible, reachable-only, conflicting, or duplicated.

### 43.1 Missing declaration

```cpp
use ns::Typo from <header.hxx>;
```

Preferred diagnostic:

```text
error: no declaration named 'Typo' in namespace 'ns' in header <header.hxx>
note: did you mean 'Type'?
```

### 43.2 Reachable but not visible

```cpp
use ns::Type from <header.hxx>;

ns::Dependency d;
```

If `Dependency` is reachable only because `Type` needs it:

```text
error: no type named 'Dependency' in namespace 'ns'
note: 'ns::Dependency' is used by imported declaration 'ns::Type' but is not visible in this context
note: use 'ns::Dependency' from <header.hxx> to name it directly
```

### 43.3 Duplicate same-context use

```text
error: duplicate use of 'std::string' in this context
note: previous use is here
```

### 43.4 Redundant nested use

```text
warning: redundant use of 'std::string'; declaration is already visible from an enclosing context
note: enclosing use is here
```

### 43.5 Attribute rejection

```text
error: attributes cannot be applied to a C++MG use-from declaration
```

## 44. Dependency output

Generated dependency files should include every physical or logical file that was read to satisfy a use-from declaration, including transitive files needed to resolve visible declarations and their reachable dependency closure.

If a used declaration depends on a transitive header, changes to that transitive header should trigger rebuilds.

## 45. Include tracing

Implementations may distinguish use-from in include tracing.

Example diagnostic style:

```text
. use <header.hxx> for ns::Type
.. reachable dependency <dependency.hxx>
```

This is implementation-defined and not part of the core language semantics.

## 46. AST, tooling, PCH, and modules

Implementations should represent use-from declarations explicitly in the AST.

A possible AST node name is:

```cpp
CXXMGUseFromDecl
```

AST/tooling consumers should be able to distinguish:

1. visible declarations;
2. reachable declarations;
3. ignored declarations.

Imported declarations and their reachability/visibility flags should be serializable in PCH, module, and AST-file formats.

Tooling may expose all involved declarations with visibility metadata.

## 47. ABI and code generation

For actually used visible declarations and their reachable dependency closure, use-from must preserve ABI and code generation behavior equivalent to using the same declarations through ordinary header inclusion.

Use-from changes source visibility, not the ABI identity of declarations.

```cpp
use ns::Type from <header.hxx>;
```

`ns::Type` is the same canonical type it would be if the header had been included, assuming the same preprocessing state and declaration universe.

## 48. Examples

### 48.1 Type import

```cpp
use std::string from <string>;

std::string name;
```

### 48.2 Scoped type import inside a class

```cpp
struct User {
  use std::string from <string>;

  std::string name;
};

std::string globalName; // invalid unless std::string is visible here
```

### 48.3 Alias import

```cpp
using String = use std::string from <string>;

String name;       // valid
std::string other; // invalid unless separately used
```

### 48.4 Function import

```cpp
use ns::make_user from <user.hxx>;

auto user = ns::make_user();
```

### 48.5 Expression-form use

```cpp
auto user = use ns::make_user from <user.hxx>;

auto other = ns::make_user(); // invalid
```

### 48.6 Wildcard namespace import

```cpp
use ns::* from <header.hxx>;

ns::A a;
ns::inner::B b;
```

### 48.7 Hidden dependency

```cpp
// header.hxx
namespace ns {
  struct Dependency {};

  struct Type {
    Dependency dep;
  };
}
```

```cpp
use ns::Type from <header.hxx>;

ns::Type t;       // valid
ns::Dependency d; // invalid
```

### 48.8 Member access through reachable type

```cpp
struct A {
  use std::string from <string>;

  std::string name;
};

void f(A a) {
  auto size = a.name.size(); // valid
  std::string s;             // invalid unless visible here
}
```

### 48.9 ADL operator

```cpp
use ns::Type from <header.hxx>;

ns::Type a, b;

bool same = a == b; // valid if operator is reachable through use-from ADL
```

### 48.10 No macro leakage

```cpp
// header.hxx
#define HEADER_MACRO 1
struct Type {};
```

```cpp
use Type from <header.hxx>;

#ifdef HEADER_MACRO
#error should not happen
#endif
```

## 49. Non-goals

Use-from does not:

1. import macros into the current file;
2. share preprocessor mutations from the used header with the using file;
3. require unrelated declarations in the used header to be semantically valid;
4. make reachable dependency declarations directly source-nameable;
5. replace normal `#include` when full textual inclusion is desired;
6. bypass normal C++ access control;
7. make class-scope imported namespaces accessible through class-qualified lookup;
8. depend on the future `alias` feature.

## 50. Summary

C++MG use-from is a selective declaration visibility mechanism.

It gives the programmer the ability to say:

```cpp
use ns::Type from <header.hxx>;
```

meaning:

> Make `ns::Type` visible here, resolve whatever is necessary to make it correct and usable, but do not include the rest of the header into my source context.

It preserves the ABI identity and semantic correctness of actually used declarations while avoiding the broad namespace and macro pollution of textual inclusion.
