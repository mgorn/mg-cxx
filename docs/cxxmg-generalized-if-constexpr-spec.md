# C++MG Generalized `if constexpr` Specification

## 1. Scope

This document specifies **generalized `if constexpr`**, a C++MG language extension that permits `if constexpr` selection in syntactic contexts beyond the standard statement form.

Standard C++ permits `if constexpr` as a statement in statement contexts. C++MG generalized `if constexpr` extends the construct so that it may appear in additional syntactic contexts, including namespace bodies, class bodies, struct bodies, union bodies, enum bodies, and other contexts where compile-time structural selection is meaningful.

The core semantic rule is:

> A generalized `if constexpr` selects one arm at compile time. The selected arm is transparent: its contents are contributed to the immediately enclosing syntactic context as though those contents had been written directly at the location of the `if constexpr`. Non-selected arms contribute nothing to the active program structure, but must still contain code or entries valid for that context.

Generalized `if constexpr` may be used to conditionally include:

- namespace-scope declarations
- type definitions
- aliases
- variables
- functions
- templates
- class members
- struct members
- union members
- enum enumerators
- local declarations
- local statements
- nested declarations
- nested type definitions

Example at class scope:

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags;
  }
};
```

For `Entity<true>`, `debugFlags` is a member.

For `Entity<false>`, `debugFlags` is not a member.

Example at namespace scope:

```cpp
inline constexpr bool UseWide = true;

if constexpr (UseWide) {
  using word = unsigned long long;
} else {
  using word = unsigned int;
}

word value;
```

If `UseWide` is `true`, `word` names `unsigned long long`.

If `UseWide` is `false`, `word` names `unsigned int`.

Example at block scope:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  x = 1; // valid for f<true>, invalid for f<false>
}
```

For `f<true>`, `x` is contributed to the enclosing block and is visible after the generalized `if constexpr`.

For `f<false>`, no declaration of `x` is contributed.

---

## 2. Relationship to standard C++ `if constexpr`

In standard C++, `if constexpr` is a statement.

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  // In standard C++, x is not visible here.
}
```

In standard C++, declarations inside the compound statement of an `if constexpr` arm are scoped to that compound statement.

C++MG generalized `if constexpr` changes this model when C++MG generalized `if constexpr` is enabled.

Under generalized `if constexpr`, the selected arm is contributed directly to the immediately enclosing context. The arm braces delimit the arm syntactically, but they do not create an additional scope for selected entries.

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  // Under generalized if constexpr, x is visible here when B is true.
  x = 1;
}
```

For `f<true>`, the function behaves as though written:

```cpp
void f_true_model() {
  int x = 0;

  x = 1;
}
```

For `f<false>`, the function behaves as though written:

```cpp
void f_false_model() {
  x = 1; // error: x does not exist
}
```

Therefore, generalized `if constexpr` is not merely a statement with discarded branches. It is a compile-time transparent selection construct.

---

## 3. Design model

Generalized `if constexpr` is compile-time source selection within the current syntactic context.

The selected arm is treated as if its contents were written directly in place of the `if constexpr`.

The non-selected arms are not active, do not declare names, do not contribute members, do not contribute enumerators, do not contribute statements, and do not produce code.

However, non-selected arms are still part of the source program. They must be parsed and must contain entries valid for the context where they appear.

This gives the feature a uniform rule:

```text
selected arm      => transparent contribution to surrounding context
non-selected arm  => no active contribution, but still valid source for that context
```

---

## 4. Terminology

### Generalized `if constexpr`

An `if constexpr` construct whose selected arm is transparently contributed to the immediately enclosing syntactic context.

### Context

The immediately enclosing syntactic region in which a generalized `if constexpr` appears.

Examples include:

- global namespace
- named namespace body
- class body
- struct body
- union body
- enum body
- function body
- compound statement
- switch statement body
- local class body

### Context entry

An item valid in the immediately enclosing context.

Examples:

- namespace declaration in a namespace body
- member declaration in a class body
- enumerator in an enum body
- statement or block declaration in a function body

### Arm

One branch of a generalized `if constexpr` chain.

```cpp
if constexpr (A) {
  // arm
} else if constexpr (B) {
  // arm
} else {
  // arm
}
```

### Selected arm

The arm selected by evaluating the chain's compile-time conditions.

### Non-selected arm

An arm not selected by the chain.

### Active entries

The entries contributed by ordinary source text and selected generalized `if constexpr` arms.

Non-selected arms contribute no active entries.

---

## 5. Availability

Generalized `if constexpr` is a C++MG language extension.

When C++MG generalized `if constexpr` is disabled, generalized `if constexpr` is ill-formed outside standard C++ statement contexts, even if the condition is `false`.

```cpp
// C++MG generalized if constexpr disabled.

struct S {
  if constexpr (false) {
    int x;
  }
};
```

This must be rejected because class-scope generalized `if constexpr` is unavailable.

When C++MG generalized `if constexpr` is enabled, it is accepted subject to the rules in this specification.

Ordinary ISO C++ statement-level `if constexpr` remains available according to the selected C++ standard mode. In C++MG mode, statement-context `if constexpr` follows the generalized transparent-arm model described by this specification.

---

## 6. Standard mode

Generalized `if constexpr` uses `if constexpr` syntax.

An implementation should require the same base language support needed for ordinary `if constexpr`. In practice, this means C++17 or later unless the implementation intentionally accepts `if constexpr` syntax as a C++MG extension in earlier language modes.

The selected C++ standard mode continues to control the validity of ordinary C++ syntax inside arms.

For example, if an arm contains a C++20 `requires` expression, that expression is valid only in a mode where the implementation supports `requires`.

---

## 7. Feature detection

An implementation should define the following macro when generalized `if constexpr` is available:

```cpp
#ifdef __cxxmg_generalized_if_constexpr
// generalized if constexpr is available
#endif
```

The macro should be defined only when generalized `if constexpr` syntax is accepted in the current language mode.

The preferred macro for the full feature is:

```cpp
__cxxmg_generalized_if_constexpr
```

An implementation may additionally define narrower feature macros for subsets of the feature, such as:

```cpp
#ifdef __cxxmg_conditional_members
// generalized if constexpr is available in class, struct, and union member contexts
#endif
```

```cpp
#ifdef __cxxmg_conditional_enumerators
// generalized if constexpr is available in enum bodies
#endif
```

For Clang-style feature detection, an implementation should expose:

```cpp
#if __has_feature(cxxmg_generalized_if_constexpr)
// generalized if constexpr is available
#endif
```

Optional narrower feature checks may include:

```cpp
#if __has_feature(cxxmg_conditional_members)
// class, struct, and union generalized if constexpr is available
#endif

#if __has_feature(cxxmg_conditional_enumerators)
// enum-body generalized if constexpr is available
#endif
```

---

## 8. Pedantic and extension diagnostics

Because generalized `if constexpr` is not ISO C++ syntax outside ordinary standard statement contexts, an implementation should be able to warn about it when the user requests strict standard-conformance diagnostics.

Default behavior when C++MG mode is enabled:

```text
accept generalized if constexpr without warning
```

Behavior with pedantic extension warnings enabled:

```text
accept generalized if constexpr, but warn that it is a C++MG language extension
```

Behavior with pedantic extension warnings promoted to errors:

```text
reject generalized if constexpr as a C++MG extension error
```

Behavior when C++MG mode is disabled:

```text
reject generalized if constexpr as unavailable syntax
```

Suggested warning:

```text
warning: generalized 'if constexpr' is a C++MG language extension
```

Suggested error when C++MG mode is disabled:

```text
error: generalized 'if constexpr' is not permitted outside C++MG mode
```

An implementation should provide a broad warning group such as:

```text
-Wcxxmg-extensions
```

An implementation may also provide a more specific subgroup such as:

```text
-Wcxxmg-generalized-if-constexpr
```

---

## 9. Syntax

### 9.1 Basic form

```cpp
if constexpr (condition) {
  context-entries
}
```

### 9.2 Else arm

```cpp
if constexpr (condition) {
  context-entries
} else {
  context-entries
}
```

### 9.3 Else-if chain

```cpp
if constexpr (A) {
  context-entries
} else if constexpr (B) {
  context-entries
} else {
  context-entries
}
```

### 9.4 Required `constexpr` in every `else if`

Every `else if` in a generalized `if constexpr` chain must be `else if constexpr`.

Valid:

```cpp
if constexpr (A) {
  using T = int;
} else if constexpr (B) {
  using T = long;
} else {
  using T = double;
}
```

Invalid:

```cpp
if constexpr (A) {
  using T = int;
} else if (B) {
  using T = long;
}
```

There is no runtime generalized `if`.

### 9.5 Grammar sketch

This grammar is descriptive, not a complete replacement for the C++ grammar.

```text
generalized-if-constexpr:
    if constexpr ( constant-expression ) generalized-if-body generalized-if-elseopt

generalized-if-body:
    { context-entry-seqopt }

generalized-if-else:
    else generalized-if-body
    else generalized-if-constexpr
```

The grammar of `context-entry-seq` is determined by the immediately enclosing context.

---

## 10. Conditions

The condition of a generalized `if constexpr` must be a constant expression contextually convertible to `bool`.

```cpp
inline constexpr bool Enabled = true;

if constexpr (Enabled) {
  void f();
}
```

Integer contextual conversion is permitted where ordinary `if constexpr` would permit it:

```cpp
if constexpr (1) {
  void f();
}
```

A non-constant condition is ill-formed:

```cpp
bool enabled();

if constexpr (enabled()) {
  void f();
}
```

A condition may be dependent:

```cpp
template <class T>
struct Storage {
  if constexpr (sizeof(T) <= sizeof(void *)) {
    T value;
  } else {
    T *value;
  }
};
```

For a dependent condition, arm selection is delayed until the relevant specialization or instantiation is formed or analyzed.

A condition may use `requires` expressions where supported by the selected standard mode:

```cpp
template <class T>
struct S {
  if constexpr (requires { typename T::value_type; }) {
    typename T::value_type value;
  }
};
```

---

## 11. Arm selection

A generalized `if constexpr` chain selects exactly one arm, or no arm if no condition is true and there is no final `else`.

Selection proceeds in source order:

1. Evaluate the first `if constexpr` condition.
2. If it is true, select that arm.
3. Otherwise, evaluate each `else if constexpr` condition in source order.
4. If one is true, select that arm.
5. Otherwise, select the final `else` arm if present.
6. Otherwise, select no arm.

```cpp
template <int Mode>
struct S {
  if constexpr (Mode == 0) {
    int a;
  } else if constexpr (Mode == 1) {
    int b;
  }
};
```

For `S<0>`, `a` exists.

For `S<1>`, `b` exists.

For `S<2>`, neither `a` nor `b` exists.

A final `else` arm is not required.

```cpp
template <bool Enabled>
struct S {
  if constexpr (Enabled) {
    int value;
  }
};
```

For `S<true>`, `value` exists.

For `S<false>`, the generalized `if constexpr` contributes no active entries.

---

## 12. Transparent arm model

The selected arm of a generalized `if constexpr` is transparent.

The braces around an arm delimit the arm syntactically, but they do not introduce an additional scope for selected entries.

The selected arm's contents are contributed to the immediately enclosing context at the location of the generalized `if constexpr`.

At namespace scope:

```cpp
if constexpr (UseWide) {
  using word = unsigned long long;
} else {
  using word = unsigned int;
}

word value;
```

The selected alias is visible after the generalized `if constexpr`.

At class scope:

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags;
  }
};
```

The selected data member becomes a member of the selected class specialization.

At enum scope:

```cpp
template <bool Debug>
enum class Flags {
  None = 0,

  if constexpr (Debug) {
    DebugEnabled = 1,
  }

  Always = 2,
};
```

The selected enumerator becomes an enumerator of the enum.

At block scope:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  } else {
    double x = 0.0;
  }

  x = x + 1;
}
```

For `f<true>`, `x` is an `int`.

For `f<false>`, `x` is a `double`.

In each case, the selected declaration has the same scope, lifetime, and initialization behavior it would have had if written directly in the enclosing block at the location of the generalized `if constexpr`.

---

## 13. Context-sensitive arm contents

The contents of each arm are interpreted according to the immediately enclosing syntactic context.

A generalized `if constexpr` arm may contain entries valid in that context, except where this specification explicitly restricts them.

This is the core context rule:

> If an entry would be valid when written directly at the location of the generalized `if constexpr`, then it is valid inside an arm of that generalized `if constexpr`, unless this specification explicitly forbids it.

Conversely:

> If an entry would not be valid when written directly at that location, then placing it inside a generalized `if constexpr` arm does not make it valid.

Examples:

```cpp
void f() {
  if constexpr (true) {
    return; // valid: return is valid in function-body context
  }
}
```

```cpp
struct S {
  if constexpr (true) {
    return; // error: return is not valid in class context
  }
};
```

```cpp
enum E {
  A,

  if constexpr (true) {
    B, // valid: B is an enumerator
  }
};
```

```cpp
enum E {
  A,

  if constexpr (true) {
    int x; // error: int x is not an enumerator
  }
};
```

---

## 14. Namespace context

At namespace scope, arms contain namespace-scope declarations.

```cpp
namespace api {
  if constexpr (sizeof(void *) == 8) {
    using word = unsigned long long;
    void process64();
  } else {
    using word = unsigned int;
    void process32();
  }
}
```

Allowed entries include declarations that are otherwise valid at namespace scope, such as:

- function declarations
- function definitions
- variable declarations
- inline variable declarations
- type aliases
- alias templates
- class definitions
- struct definitions
- union definitions
- enum definitions
- namespace definitions
- namespace aliases
- template declarations
- explicit specializations, where otherwise valid
- using-declarations
- using-directives
- linkage specifications
- `static_assert` declarations
- empty declarations

Example:

```cpp
inline constexpr bool Fast = true;

if constexpr (Fast) {
  void process() {
    // fast implementation
  }
} else {
  void process() {
    // portable implementation
  }
}
```

Only one `process` definition exists in the active declaration set.

---

## 15. Class, struct, and union context

Inside a class, struct, or union body, arms contain member-specification entries.

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags;
    void dump() const;
  }
};
```

Allowed entries include declarations otherwise valid in the immediately enclosing class, struct, or union, such as:

- non-static data members
- static data members
- inline static data members
- member function declarations
- member function definitions
- static member functions
- constructors
- destructors
- conversion functions
- defaulted functions
- deleted functions
- nested classes
- nested structs
- nested unions
- nested enums
- type aliases
- alias templates
- member templates
- using-declarations
- using-enum declarations
- `static_assert` declarations
- empty declarations

Selected entries become members of the enclosing class, struct, or union.

```cpp
template <bool B>
struct S {
  int a;

  if constexpr (B) {
    int b;
  }

  int c;
};
```

For `S<true>`, the active member order is:

```cpp
int a;
int b;
int c;
```

For `S<false>`, the active member order is:

```cpp
int a;
int c;
```

### 15.1 Access labels

Access labels are not permitted inside generalized `if constexpr` arms in class, struct, or union context.

Invalid:

```cpp
class S {
  if constexpr (true) {
  public:
    int x;
  }
};
```

Access labels must be placed outside the generalized `if constexpr`.

Valid:

```cpp
class S {
public:
  if constexpr (true) {
    int x;
  }

private:
  if constexpr (true) {
    int y;
  }
};
```

`x` is public.

`y` is private.

### 15.2 Friend declarations

Friend declarations are not permitted inside generalized `if constexpr` arms in class, struct, or union context.

Invalid:

```cpp
struct S {
  if constexpr (true) {
    friend void inspect(S);
  }
};
```

This avoids defining conditional namespace injection and conditional friend lookup behavior.

Friend support may be specified separately in a future revision.

---

## 16. Enum context

Inside an enum body, arms contain enumerator entries.

```cpp
template <bool Debug>
enum class Flags {
  None = 0,

  if constexpr (Debug) {
    DebugEnabled = 1,
    Verbose = 2,
  }

  Always = 4,
};
```

If `Debug` is true, the active enumerators are:

```cpp
None = 0,
DebugEnabled = 1,
Verbose = 2,
Always = 4
```

If `Debug` is false, the active enumerators are:

```cpp
None = 0,
Always = 4
```

A generalized `if constexpr` in an enum body contributes selected enumerators to the enclosing enumerator-list.

Non-selected enumerators do not exist.

The selected enumerators participate in enumerator value assignment as though written directly at that location.

Example:

```cpp
template <bool B>
enum E {
  A = 0,

  if constexpr (B) {
    X,
    Y,
  }

  Z,
};
```

For `E<true>`, the enumerators are:

```cpp
A = 0,
X = 1,
Y = 2,
Z = 3
```

For `E<false>`, the enumerators are:

```cpp
A = 0,
Z = 1
```

Only selected enumerators participate in:

- enumerator lookup
- implicit enumerator value assignment
- duplicate enumerator checking
- enum range analysis
- diagnostics for the active enum
- debug information
- generated metadata, where applicable

### 16.1 Enum separator handling

A generalized `if constexpr` inside an enum body occupies a position in the enum's enumerator-list.

The selected arm contributes zero or more enumerators at that position.

Commas before, after, and inside selected arms are interpreted as separators for the resulting active enumerator-list.

An implementation should accept natural enum-list spelling such as:

```cpp
template <bool B>
enum E {
  A,

  if constexpr (B) {
    X,
    Y,
  }

  Z,
};
```

For `E<true>`, this is equivalent to:

```cpp
enum E {
  A,
  X,
  Y,
  Z,
};
```

For `E<false>`, this is equivalent to:

```cpp
enum E {
  A,
  Z,
};
```

A non-selected arm must not leave behind invalid separator structure in the active enum. The generalized `if constexpr` construct as a whole is responsible for producing a valid active enumerator-list after selection.

---

## 17. Statement and block context

Inside a function body or other statement context, generalized `if constexpr` may contain statements and declarations that are valid in that context.

```cpp
template <bool Debug>
void f() {
  if constexpr (Debug) {
    int x = 0;
    x += 1;
    log_debug(x);
  } else {
    run_normal();
  }
}
```

The selected arm contributes its statements and declarations to the enclosing statement sequence.

For `f<true>`, the function behaves as though written:

```cpp
void f_true_model() {
  int x = 0;
  x += 1;
  log_debug(x);
}
```

For `f<false>`, the function behaves as though written:

```cpp
void f_false_model() {
  run_normal();
}
```

Statements are valid inside generalized `if constexpr` arms when statements are valid in the enclosing context.

Valid:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
    x += 1;
    return;
  }
}
```

Invalid:

```cpp
struct S {
  if constexpr (true) {
    return; // error: return statement is not valid in class scope
  }
};
```

### 17.1 Block-scope declaration visibility

Because the selected arm is transparent, selected block-scope declarations are visible after the generalized `if constexpr` if they would be visible after being written directly at that location.

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    using T = int;
  } else {
    using T = float;
  }

  T value{};
}
```

For `f<true>`, `T` names `int`.

For `f<false>`, `T` names `float`.

Local variables follow the same rule:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int value = 1;
  } else {
    double value = 1.5;
  }

  value = value + 1;
}
```

For `f<true>`, `value` is an `int`.

For `f<false>`, `value` is a `double`.

### 17.2 Block-scope lifetime

A selected local variable has the same lifetime it would have if written directly in the enclosing block at the generalized `if constexpr` location.

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    Tracer t;
  }

  use();

  // For f<true>, t is destroyed at the end of the enclosing block.
}
```

For `f<true>`, this behaves as though written:

```cpp
void f_true_model() {
  Tracer t;

  use();
}
```

For `f<false>`, no `Tracer t` exists.

### 17.3 Labels and control flow

Labels and control-flow statements are permitted inside generalized `if constexpr` arms when they are valid in the enclosing statement context.

Selected labels are labels of the enclosing function, subject to ordinary C++ label and jump rules.

Non-selected labels do not exist.

```cpp
template <bool B>
void f() {
  if constexpr (B) {
  label:
    return;
  }

  if constexpr (B) {
    goto label;
  }
}
```

For `f<true>`, `label` exists.

For `f<false>`, `label` does not exist.

Jumps into, out of, or across selected entries are subject to the same restrictions they would have if the selected entries were written directly in the enclosing statement sequence.

---

## 18. Nested generalized `if constexpr`

Generalized `if constexpr` constructs may be nested inside arms.

Selected nested constructs are flattened recursively into the enclosing context.

```cpp
template <bool A, bool B>
struct S {
  if constexpr (A) {
    int a;

    if constexpr (B) {
      int b;
    }

    int c;
  }
};
```

For `S<true, true>`, the active member order is:

```cpp
int a;
int b;
int c;
```

For `S<true, false>`, the active member order is:

```cpp
int a;
int c;
```

For `S<false, true>`, none of `a`, `b`, or `c` exists.

The same rule applies in namespace, enum, and block contexts.

Example at block scope:

```cpp
template <bool A, bool B>
void f() {
  if constexpr (A) {
    int a = 0;

    if constexpr (B) {
      int b = 1;
    }

    int c = 2;
  }

  // For f<true, true>: a, b, and c are visible.
  // For f<true, false>: a and c are visible.
  // For f<false, true>: none are visible.
}
```

---

## 19. Non-selected arms

Non-selected arms are not preprocessor-disabled source text.

They are still parsed.

They must contain entries valid for the immediately enclosing context.

A non-selected arm does not make invalid code valid.

Invalid:

```cpp
if constexpr (false) {
  int bad[-1];
}
```

Invalid:

```cpp
struct S {
  if constexpr (false) {
    virtual int x;
  }
};
```

Invalid:

```cpp
enum E {
  A,

  if constexpr (false) {
    int x;
  }
};
```

The enum example is invalid because `int x;` is not an enumerator entry.

Invalid:

```cpp
if constexpr (false) {
  int x = ;
}
```

However, non-selected arms do not contribute active entries.

Therefore, non-selected arms do not affect:

- ordinary lookup
- overload resolution
- class layout
- union member sets
- enum enumerator sets
- aggregate initialization
- aggregate status
- duplicate-declaration checking
- implicit special member generation
- generated code
- ABI
- local variable lifetime
- emitted debug information for active code

Example:

```cpp
struct S {
  if constexpr (false) {
    int x;
  }

  int x;
};
```

This is valid because the conditional `x` is not selected.

---

## 20. Validation of non-selected arms

Non-selected arms must be valid source for the context in which they appear.

This includes syntactic validity and semantic validity needed to form a valid representation of the arm.

For example, a non-selected arm may not contain:

```cpp
if constexpr (false) {
  UnknownType x;
}
```

if `UnknownType` is not a valid type name in that context.

A non-selected arm may not contain:

```cpp
if constexpr (false) {
  int bad[-1];
}
```

because the declaration is inherently invalid.

A non-selected arm may not contain:

```cpp
struct S {
  if constexpr (false) {
    virtual int x;
  }
};
```

because `virtual int x;` is not a valid member declaration.

However, active effects of non-selected valid entries are not applied. A non-selected valid declaration does not declare a name in the active program structure, does not affect overload resolution, does not affect layout, and does not generate code.

---

## 21. Static assertions in non-selected arms

A `static_assert` inside a selected arm is evaluated normally.

A `static_assert` inside a non-selected arm is not active for that specialization or instantiation.

```cpp
template <bool B>
struct S {
  if constexpr (B) {
    static_assert(true);
  } else {
    static_assert(false);
  }
};

S<true> ok;
```

For `S<true>`, the `static_assert(false)` in the non-selected arm does not fire.

The `static_assert` declaration must still be syntactically valid.

This rule follows the general active-entry model: a non-selected arm contributes no active entries and therefore does not evaluate active declaration effects.

---

## 22. Declaration and entry ordering

Selected entries preserve their source order.

Entries before a generalized `if constexpr` are considered before entries selected from it.

Entries selected from a generalized `if constexpr` are considered before entries that follow it.

Example at namespace scope:

```cpp
using A = int;

if constexpr (true) {
  using B = A;
}

B value;
```

This is valid.

Example at class scope:

```cpp
struct S {
  if constexpr (true) {
    using T = int;
  }

  T value;
};
```

This is valid.

Within a selected arm, ordinary source-order rules apply.

Invalid:

```cpp
struct S {
  if constexpr (true) {
    T value;
    using T = int;
  }
};
```

This is invalid because `T` is used before it is declared, just as it would be invalid if written directly in the class body.

---

## 23. Name lookup

Selected entries participate in ordinary lookup as entries of the immediately enclosing context.

Non-selected entries do not participate in ordinary lookup.

### 23.1 Namespace lookup

```cpp
namespace n {
  if constexpr (true) {
    void f();
  } else {
    void g();
  }
}

void test() {
  n::f(); // valid
  n::g(); // error
}
```

### 23.2 Class member lookup

```cpp
template <bool B>
struct S {
  if constexpr (B) {
    int x;
  }
};

void test() {
  S<true> a;
  a.x = 1; // valid

  S<false> b;
  b.x = 1; // error
}
```

### 23.3 Enum lookup

```cpp
template <bool B>
enum class E {
  A,

  if constexpr (B) {
    X,
  }
};

auto a = E<true>::X;  // valid
auto b = E<false>::X; // error
```

### 23.4 Block lookup

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  x = 1; // valid for f<true>, invalid for f<false>
}
```

---

## 24. Diagnostic lookup of non-selected entries

An implementation may retain entries from non-selected arms for diagnostics.

When ordinary lookup fails, the implementation may search non-selected arms to produce better diagnostics.

Example:

```cpp
template <bool Debug>
struct Entity {
  if constexpr (Debug) {
    int debugFlags;
  }
};

void f(Entity<false> e) {
  e.debugFlags = 0;
}
```

Suggested diagnostic:

```text
error: no member named 'debugFlags' in 'Entity<false>'
note: 'debugFlags' is declared in an if constexpr arm that is not selected for this specialization
```

Enum example:

```cpp
template <bool Debug>
enum class Flags {
  None = 0,

  if constexpr (Debug) {
    DebugEnabled = 1,
  }
};

auto x = Flags<false>::DebugEnabled;
```

Suggested diagnostic:

```text
error: no enumerator named 'DebugEnabled' in 'Flags<false>'
note: 'DebugEnabled' is declared in an if constexpr arm that is not selected for this specialization
```

Namespace example:

```cpp
namespace n {
  if constexpr (false) {
    void hidden();
  }
}

void test() {
  n::hidden();
}
```

Suggested diagnostic:

```text
error: no function named 'hidden' in namespace 'n'
note: 'hidden' is declared in an if constexpr arm that is not selected
```

Block-scope example:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  x = 1;
}

template void f<false>();
```

Suggested diagnostic:

```text
error: use of undeclared identifier 'x'
note: 'x' is declared in an if constexpr arm that is not selected for this instantiation
```

Diagnostic lookup does not make non-selected entries visible or usable.

---

## 25. Conditional type definitions

A generalized `if constexpr` may conditionally define a class, struct, union, or enum wherever such a definition is valid.

### 25.1 Namespace-scope type definition

```cpp
inline constexpr bool Wide = true;

if constexpr (Wide) {
  struct Storage {
    long long value;
  };
} else {
  struct Storage {
    int value;
  };
}

Storage s;
```

If `Wide` is true, `Storage` is the first definition.

If `Wide` is false, `Storage` is the second definition.

The non-selected definition does not define a type in the active program structure.

### 25.2 Local type definition

```cpp
template <bool Wide>
void f() {
  if constexpr (Wide) {
    struct Storage {
      long long value;
    };
  } else {
    struct Storage {
      int value;
    };
  }

  Storage s{};
}
```

For `f<true>`, `Storage::value` has type `long long`.

For `f<false>`, `Storage::value` has type `int`.

### 25.3 Nested type definition

```cpp
template <bool Wide>
struct Outer {
  if constexpr (Wide) {
    struct Storage {
      long long value;
    };
  } else {
    struct Storage {
      int value;
    };
  }
};
```

`Outer<true>::Storage` and `Outer<false>::Storage` are different selected nested type definitions.

---

## 26. Conditional functions

Functions may be conditionally declared or defined wherever function declarations or definitions are valid.

```cpp
inline constexpr bool Fast = true;

if constexpr (Fast) {
  void process() {
    // fast implementation
  }
} else {
  void process() {
    // portable implementation
  }
}
```

Only one `process` definition exists in the active declaration set.

Selected functions participate in ordinary overload resolution.

Non-selected functions do not participate.

```cpp
template <bool HasInt>
struct S {
  void f(double);

  if constexpr (HasInt) {
    void f(int);
  }
};
```

For `S<true>`, overload resolution sees both `f(double)` and `f(int)`.

For `S<false>`, overload resolution sees only `f(double)`.

---

## 27. Conditional variables

Variables may be conditionally declared wherever variable declarations are valid.

### 27.1 Namespace-scope variables

```cpp
inline constexpr bool Debug = true;

if constexpr (Debug) {
  inline int log_level = 2;
} else {
  inline int log_level = 0;
}
```

Only one `log_level` exists.

### 27.2 Block-scope variables

```cpp
template <bool Floating>
void f() {
  if constexpr (Floating) {
    double value = 0.0;
  } else {
    int value = 0;
  }

  value = value + 1;
}
```

For `f<true>`, `value` is a `double`.

For `f<false>`, `value` is an `int`.

The selected variable has ordinary initialization, storage duration, and lifetime as though written directly at the generalized `if constexpr` location.

### 27.3 Class data members

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags;
  }
};
```

For `Entity<true>`, `debugFlags` exists.

For `Entity<false>`, `debugFlags` does not exist.

---

## 28. Conditional type aliases

Type aliases may be conditionally declared.

At namespace scope:

```cpp
if constexpr (sizeof(void *) == 8) {
  using native_word = unsigned long long;
} else {
  using native_word = unsigned int;
}

native_word value;
```

At class scope:

```cpp
template <bool Wide>
struct S {
  if constexpr (Wide) {
    using value_type = long long;
  } else {
    using value_type = int;
  }
};
```

At block scope:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    using T = int;
  } else {
    using T = float;
  }

  T value{};
}
```

---

## 29. Conditional templates

Template declarations may appear inside generalized `if constexpr` arms where template declarations are otherwise valid.

```cpp
inline constexpr bool UsePointerBox = true;

if constexpr (UsePointerBox) {
  template <class T>
  struct Box {
    T *value;
  };
} else {
  template <class T>
  struct Box {
    T value;
  };
}

Box<int> b;
```

Only one `Box` template is declared.

Member templates may also be conditionally declared inside classes:

```cpp
template <bool Enabled>
struct S {
  if constexpr (Enabled) {
    template <class T>
    void set(T value);
  }
};
```

---

## 30. Conditional namespaces

Namespace definitions may appear inside generalized `if constexpr` arms where namespace definitions are otherwise valid.

```cpp
inline constexpr bool UseV2 = true;

if constexpr (UseV2) {
  namespace api {
    void v2_function();
  }
} else {
  namespace api {
    void v1_function();
  }
}
```

Only the selected namespace body contributes declarations.

Namespace definitions are not valid inside class, union, enum, or ordinary block scopes, so they are not valid in generalized `if constexpr` arms in those contexts.

---

## 31. Conditional class, struct, and union members

Generalized `if constexpr` inside a class, struct, or union contributes selected members to the enclosing class, struct, or union.

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags;
  }
};
```

For `Entity<true>`, `debugFlags` is a member.

For `Entity<false>`, `debugFlags` is not a member.

Selected data members participate in layout at the location of the generalized `if constexpr`.

```cpp
template <bool B>
struct S {
  char a;

  if constexpr (B) {
    int b;
  }

  char c;
};
```

For `S<true>`, layout is as though written:

```cpp
struct S_true_model {
  char a;
  int b;
  char c;
};
```

For `S<false>`, layout is as though written:

```cpp
struct S_false_model {
  char a;
  char c;
};
```

Non-selected data members do not consume storage.

---

## 32. Conditional union members

Generalized `if constexpr` is permitted inside unions.

```cpp
template <bool Integer>
union Value {
  if constexpr (Integer) {
    int i;
  } else {
    float f;
  }
};
```

`Value<true>` has member `i`.

`Value<false>` has member `f`.

Only selected entries participate in the union member set.

All ordinary C++ union rules apply to the selected member set.

Example:

```cpp
template <bool Debug>
union U {
  int i;

  if constexpr (Debug) {
    float f;
  }
};
```

`U<true>` has both `i` and `f`.

`U<false>` has only `i`.

---

## 33. Conditional enum values

Generalized `if constexpr` is permitted inside enum bodies.

```cpp
template <bool Debug>
enum class Flags {
  None = 0,

  if constexpr (Debug) {
    DebugEnabled = 1,
    Verbose = 2,
  }

  Always = 4,
};
```

For `Flags<true>`, `DebugEnabled` and `Verbose` exist.

For `Flags<false>`, they do not exist.

Selected enumerators participate in implicit enumerator value assignment.

```cpp
template <bool Extra>
enum E {
  A,

  if constexpr (Extra) {
    B,
    C,
  }

  D,
};
```

For `E<true>`:

```cpp
A = 0,
B = 1,
C = 2,
D = 3
```

For `E<false>`:

```cpp
A = 0,
D = 1
```

Duplicate enumerators are diagnosed based on the selected enumerator set.

```cpp
template <bool B>
enum E {
  X,

  if constexpr (B) {
    X, // error for E<true>
  }
};
```

For `E<false>`, the conditional `X` is not selected and does not conflict.

---

## 34. Conditional constructors, destructors, and conversion functions

Constructors, destructors, and conversion functions may be conditionally declared inside class definitions if the selected member set is otherwise valid.

```cpp
template <bool HasCtor>
struct S {
  int value;

  if constexpr (HasCtor) {
    S(int v) : value(v) {}
  }
};
```

For `S<true>`, `S(int)` exists.

For `S<false>`, it does not.

Conditionally selected constructors affect construction, overload resolution, aggregate status, triviality, and type properties.

```cpp
template <bool Tracked>
struct S {
  if constexpr (Tracked) {
    ~S();
  }
};
```

For `S<true>`, the destructor exists.

For `S<false>`, the class has the destructor it would otherwise have.

If selected declarations create an invalid special-member set, the program is ill-formed.

---

## 35. Defaulted and deleted functions

Defaulted and deleted functions may appear inside generalized `if constexpr` arms where they would otherwise be valid.

```cpp
template <bool Copyable>
struct S {
  if constexpr (Copyable) {
    S(const S &) = default;
  } else {
    S(const S &) = delete;
  }
};
```

For `S<true>`, the copy constructor is defaulted.

For `S<false>`, the copy constructor is deleted.

Only the selected declaration affects the class.

---

## 36. Aggregate initialization and type properties

Selected entries affect aggregate initialization and type properties normally.

Non-selected entries do not.

```cpp
template <bool B>
struct S {
  int a;

  if constexpr (B) {
    int b;
  }

  int c;
};

S<true> x{1, 2, 3};
S<false> y{1, 3};
```

For `S<true>`, the aggregate elements are:

```text
a, b, c
```

For `S<false>`, the aggregate elements are:

```text
a, c
```

An initializer for a non-selected member is ill-formed.

```cpp
S<false> bad{1, 2, 3};
```

Selected entries affect, where applicable:

- size
- alignment
- standard-layout status
- triviality
- aggregate status
- polymorphism
- literal type status
- implicit special member generation
- constructibility
- destructibility
- assignability
- copyability
- moveability

---

## 37. Duplicate declarations and conflicts

Duplicate or conflicting declarations are diagnosed based on the active entries only.

```cpp
template <bool B>
struct S {
  int value;

  if constexpr (B) {
    int value;
  }
};
```

`S<true>` is ill-formed because it has two active data members named `value`.

`S<false>` is valid because the conditional `value` is not selected.

Declarations in mutually exclusive arms may use the same name with different types or meanings.

```cpp
template <bool Wide>
struct S {
  if constexpr (Wide) {
    long long value;
  } else {
    int value;
  }
};
```

`S<true>::value` has type `long long`.

`S<false>::value` has type `int`.

This is valid because both declarations are never active in the same specialization.

At namespace scope:

```cpp
inline constexpr bool Wide = true;

if constexpr (Wide) {
  struct Storage {
    long long value;
  };
} else {
  struct Storage {
    int value;
  };
}
```

Only one `Storage` definition exists in the active program structure, so this is not a redefinition.

At block scope:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int value = 0;
  } else {
    double value = 0.0;
  }

  value = value + 1;
}
```

Only one `value` declaration exists in each instantiation.

---

## 38. Out-of-class definitions

A conditionally selected member may have an out-of-class definition only for specializations where that member exists.

```cpp
template <bool Enabled>
struct S {
  if constexpr (Enabled) {
    void f();
  }
};

template <>
void S<true>::f() {}
```

This is valid.

```cpp
template <>
void S<false>::f() {}
```

This is ill-formed because `S<false>::f` does not exist.

For dependent generalized `if constexpr` member declarations, the implementation must determine whether the member exists in the specialization being defined.

---

## 39. Explicit instantiation

Explicit instantiation uses the active entries for the specialization being instantiated.

```cpp
template <bool B>
struct S {
  if constexpr (B) {
    void f();
  }
};

template struct S<true>;
template struct S<false>;
```

`S<true>` has `f`.

`S<false>` does not have `f`.

The explicit instantiation of `S<false>` must not instantiate, emit, or require definitions for members that are not selected for `S<false>`.

---

## 40. Templates and dependent conditions

A generalized `if constexpr` condition may depend on template parameters.

```cpp
template <class T, bool StoreInline>
struct OptionalStorage {
  if constexpr (StoreInline) {
    T value;
  } else {
    T *ptr;
  }
};
```

Each specialization has its own active entries.

```cpp
OptionalStorage<int, true> a;  // has value
OptionalStorage<int, false> b; // has ptr
```

At block scope:

```cpp
template <class T>
void f(T t) {
  if constexpr (sizeof(T) <= sizeof(void *)) {
    T value = t;
  } else {
    T *value = &t;
  }

  (void)value;
}
```

Each instantiation selects one block-scope declaration.

Conditions may depend on:

- type template parameters
- non-type template parameters
- template template parameters
- `sizeof`
- type traits
- `requires` expressions where supported
- `constexpr` static data members
- other constant expressions valid at that point

---

## 41. Interaction with inheritance

Generalized `if constexpr` may appear inside classes with base classes.

```cpp
template <bool Debug>
struct Entity : Base {
  int id;

  if constexpr (Debug) {
    int debugFlags;
  }
};
```

Generalized `if constexpr` does not conditionally control the base-specifier list.

Invalid:

```cpp
template <bool Debug>
struct Entity
  if constexpr (Debug) : DebugBase
{
};
```

Conditional base clauses are outside the scope of this feature.

Selected members interact with inherited members according to ordinary C++ lookup, hiding, access, and overload rules.

---

## 42. Optional entry use

Code that uses a conditionally selected entry must only do so when that entry exists.

Valid:

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

Invalid for `Entity<false>`:

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags = 0;
  }

  void clearDebugFlags() {
    debugFlags = 0;
  }
};
```

The member `debugFlags` does not exist in `Entity<false>`.

At namespace scope:

```cpp
if constexpr (false) {
  void hidden();
}

void test() {
  hidden();
}
```

This is ill-formed because `hidden` is not declared.

At block scope:

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  x = 1;
}
```

This is valid for `f<true>` and invalid for `f<false>`.

---

## 43. `decltype`, `sizeof`, and `requires`

Queries about conditionally selected entries behave according to whether the entry exists in the active program structure.

```cpp
template <bool Debug>
struct Entity {
  if constexpr (Debug) {
    int debugFlags;
  }
};

static_assert(sizeof(Entity<false>) <= sizeof(Entity<true>));
```

A `requires` expression can check for conditionally present members:

```cpp
template <class T>
concept HasDebugFlags = requires(T t) {
  t.debugFlags;
};

static_assert(HasDebugFlags<Entity<true>>);
static_assert(!HasDebugFlags<Entity<false>>);
```

`decltype` of a non-selected entry is ill-formed unless protected by a mechanism such as `requires`.

```cpp
using T = decltype(Entity<false>{}.debugFlags);
```

This is ill-formed.

---

## 44. ABI and code generation

Generalized `if constexpr` can affect:

- namespace declarations
- class layout
- union member sets
- enum enumerator sets
- overload sets
- constructors
- destructors
- conversion functions
- nested types
- local declarations
- generated symbols
- emitted statements
- local variable lifetime
- debug information

Different specializations of a class template may have different ABI-relevant properties.

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    const char *debugName;
  }
};
```

`Entity<true>` and `Entity<false>` may have different layouts.

Generated symbols for selected declarations use the same mangling and linkage rules they would use if the selected entries had been written directly in the enclosing context.

Non-selected entries must not produce symbols.

At block scope, non-selected statements must not produce code.

---

## 45. Linkage and ODR

Selected declarations follow ordinary C++ linkage and one-definition-rule rules.

Non-selected declarations do not contribute declarations or definitions to the active program structure and do not create ODR conflicts.

```cpp
inline constexpr bool UseA = true;

if constexpr (UseA) {
  struct X {
    int a;
  };
} else {
  struct X {
    int b;
  };
}
```

Only one definition of `X` exists in the active program structure.

If selected declarations produce an ODR violation, the program is ill-formed under ordinary C++ rules.

```cpp
struct X {};

if constexpr (true) {
  struct X {};
}
```

This is ill-formed because the selected declaration redefines `X`.

---

## 46. AST, tooling, serialization, PCH, and modules

An implementation should represent generalized `if constexpr` in the AST.

The AST representation should preserve:

- the generalized `if constexpr` node
- each arm
- each arm condition
- entries written inside selected arms
- entries written inside non-selected arms
- source locations for conditions and arm bodies
- selected-arm information for a particular specialization or instantiation, when known

AST dumps should show generalized `if constexpr` structure.

Source-level tooling should be able to inspect both selected and non-selected arms.

Semantic tooling should be able to determine the active entries when the required context is available.

Headers containing generalized `if constexpr` may be used in precompiled headers.

Modules may serialize generalized `if constexpr` AST nodes.

Deserialization must preserve generalized `if constexpr` structure.

For dependent conditions, arm selection may occur after deserialization when the relevant specialization or instantiation is formed or analyzed.

---

## 47. Diagnostics

Diagnostics should make it clear whether an entry is selected, non-selected, unavailable, or invalid.

### 47.1 Feature disabled

```cpp
struct S {
  if constexpr (true) {
    int x;
  }
};
```

Suggested diagnostic:

```text
error: generalized 'if constexpr' is not permitted outside C++MG mode
```

### 47.2 Pedantic extension warning

```cpp
struct S {
  if constexpr (true) {
    int x;
  }
};
```

Suggested diagnostic when extension warnings are requested:

```text
warning: generalized 'if constexpr' is a C++MG language extension
```

### 47.3 Missing `constexpr` in `else if`

```cpp
if constexpr (A) {
  using T = int;
} else if (B) {
  using T = long;
}
```

Suggested diagnostic:

```text
error: generalized 'if constexpr' chains require 'else if constexpr'
```

### 47.4 Non-constant condition

```cpp
bool enabled();

if constexpr (enabled()) {
  void f();
}
```

Suggested diagnostic:

```text
error: generalized 'if constexpr' condition is not a constant expression
```

### 47.5 Context-invalid entry

```cpp
struct S {
  if constexpr (true) {
    return;
  }
};
```

Suggested diagnostic:

```text
error: return statement is not valid in class scope
note: generalized 'if constexpr' arms must contain entries valid in the enclosing context
```

### 47.6 Access label inside class arm

```cpp
struct S {
  if constexpr (true) {
  public:
    int x;
  }
};
```

Suggested diagnostic:

```text
error: access specifiers are not allowed inside generalized 'if constexpr' arms
note: place 'public:', 'private:', or 'protected:' before or after the generalized 'if constexpr'
```

### 47.7 Friend declaration inside class arm

```cpp
struct S {
  if constexpr (true) {
    friend void f(S);
  }
};
```

Suggested diagnostic:

```text
error: friend declarations are not allowed inside generalized 'if constexpr' arms
```

### 47.8 Use of non-selected member

```cpp
template <bool B>
struct S {
  if constexpr (B) {
    int x;
  }
};

void f(S<false> s) {
  s.x = 0;
}
```

Suggested diagnostic:

```text
error: no member named 'x' in 'S<false>'
note: 'x' is declared in an if constexpr arm that is not selected for this specialization
```

### 47.9 Use of non-selected local

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  x = 1;
}

template void f<false>();
```

Suggested diagnostic:

```text
error: use of undeclared identifier 'x'
note: 'x' is declared in an if constexpr arm that is not selected for this instantiation
```

### 47.10 Use of non-selected enumerator

```cpp
template <bool B>
enum class E {
  A,

  if constexpr (B) {
    X,
  }
};

auto x = E<false>::X;
```

Suggested diagnostic:

```text
error: no enumerator named 'X' in 'E<false>'
note: 'X' is declared in an if constexpr arm that is not selected for this specialization
```

### 47.11 Duplicate selected declaration

```cpp
struct S {
  int x;

  if constexpr (true) {
    int x;
  }
};
```

Suggested diagnostic:

```text
error: duplicate member 'x'
note: previous declaration is here
note: generalized 'if constexpr' arm is selected
```

### 47.12 Invalid non-selected entry

```cpp
if constexpr (false) {
  int bad[-1];
}
```

Suggested diagnostic:

```text
error: array size is negative
note: entries inside non-selected generalized 'if constexpr' arms must still be valid
```

---

## 48. Examples

### 48.1 Conditional namespace alias

```cpp
if constexpr (sizeof(void *) == 8) {
  using native_word = unsigned long long;
} else {
  using native_word = unsigned int;
}

native_word value;
```

### 48.2 Conditional structure definition

```cpp
inline constexpr bool Wide = true;

if constexpr (Wide) {
  struct Storage {
    long long value;
  };
} else {
  struct Storage {
    int value;
  };
}

Storage s;
```

### 48.3 Conditional function implementation

```cpp
inline constexpr bool Fast = true;

if constexpr (Fast) {
  void process() {
    // fast implementation
  }
} else {
  void process() {
    // portable implementation
  }
}
```

### 48.4 Conditional class member

```cpp
template <bool Debug>
struct Entity {
  int id;

  if constexpr (Debug) {
    int debugFlags;
  }
};
```

### 48.5 Conditional local type

```cpp
template <bool Wide>
void f() {
  if constexpr (Wide) {
    struct Local {
      long long value;
    };
  } else {
    struct Local {
      int value;
    };
  }

  Local x{};
}
```

### 48.6 Conditional local variable

```cpp
template <bool Floating>
void f() {
  if constexpr (Floating) {
    double value = 0.0;
  } else {
    int value = 0;
  }

  value = value + 1;
}
```

### 48.7 Conditional union member

```cpp
template <bool Integer>
union Value {
  if constexpr (Integer) {
    int i;
  } else {
    float f;
  }
};
```

### 48.8 Conditional enum values

```cpp
template <bool Debug>
enum class Flags {
  None = 0,

  if constexpr (Debug) {
    DebugEnabled = 1,
    Verbose = 2,
  }

  Always = 4,
};
```

---

## 49. Minimal accepted examples

### 49.1 Namespace declaration

```cpp
if constexpr (true) {
  void f();
}

void g() {
  f();
}
```

### 49.2 Conditional type definition

```cpp
if constexpr (true) {
  struct S {
    int x;
  };
} else {
  struct S {
    float x;
  };
}

S s;
```

### 49.3 Class member

```cpp
struct S {
  if constexpr (true) {
    int x;
  }
};

int main() {
  S s;
  s.x = 1;
}
```

### 49.4 Non-selected class member

```cpp
struct S {
  if constexpr (false) {
    int x;
  }

  int y;
};

int main() {
  S s;
  s.y = 1;
}
```

### 49.5 Block-scope alias

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    using T = int;
  } else {
    using T = float;
  }

  T value{};
}
```

### 49.6 Block-scope variable escapes selected arm

```cpp
template <bool B>
void f() {
  if constexpr (B) {
    int x = 0;
  }

  if constexpr (B) {
    x = 1;
  }
}
```

### 49.7 Union

```cpp
template <bool B>
union U {
  if constexpr (B) {
    int i;
  } else {
    float f;
  }
};

int main() {
  U<true> a;
  a.i = 1;

  U<false> b;
  b.f = 1.0f;
}
```

### 49.8 Enum

```cpp
template <bool B>
enum class E {
  A,

  if constexpr (B) {
    X,
  }

  Z,
};

auto a = E<true>::X;
```

---

## 50. Minimal rejected examples

### 50.1 Feature disabled

```cpp
struct S {
  if constexpr (true) {
    int x;
  }
};
```

Rejected when generalized `if constexpr` is not enabled.

### 50.2 Runtime condition

```cpp
bool enabled();

if constexpr (enabled()) {
  void f();
}
```

### 50.3 Missing `constexpr` in `else if`

```cpp
if constexpr (A) {
  using T = int;
} else if (B) {
  using T = long;
}
```

### 50.4 Context-invalid statement

```cpp
struct S {
  if constexpr (true) {
    return;
  }
};
```

### 50.5 Context-invalid declaration

```cpp
enum E {
  A,

  if constexpr (true) {
    int x;
  }
};
```

### 50.6 Access label in class arm

```cpp
struct S {
  if constexpr (true) {
  public:
    int x;
  }
};
```

### 50.7 Friend declaration in class arm

```cpp
struct S {
  if constexpr (true) {
    friend void f(S);
  }
};
```

### 50.8 Non-selected declaration use

```cpp
if constexpr (false) {
  void hidden();
}

void test() {
  hidden();
}
```

### 50.9 Duplicate selected declaration

```cpp
struct S {
  int x;

  if constexpr (true) {
    int x;
  }
};
```

### 50.10 Invalid non-selected entry

```cpp
if constexpr (false) {
  int bad[-1];
}
```

---

## 51. Recommended conformance tests

An implementation should test at least the following behavior.

### 51.1 Parsing

- namespace-scope generalized `if constexpr`
- class-scope generalized `if constexpr`
- struct-scope generalized `if constexpr`
- union-scope generalized `if constexpr`
- enum-body generalized `if constexpr`
- block-scope generalized `if constexpr`
- local class generalized `if constexpr`
- nested class generalized `if constexpr`
- empty selected arm
- empty non-selected arm
- final `else`
- `else if constexpr`
- missing `constexpr` in `else if`
- nested generalized `if constexpr`

### 51.2 Feature availability

- accepted when C++MG mode is enabled
- rejected when C++MG mode is disabled
- rejected when disabled even if condition is false
- `__cxxmg_generalized_if_constexpr`
- `__has_feature(cxxmg_generalized_if_constexpr)`
- pedantic warning
- pedantic warning promoted to error
- extension warning suppression

### 51.3 Conditions

- `true`
- `false`
- integer contextual conversion
- dependent boolean parameter
- dependent `sizeof` expression
- `requires` expression where supported
- non-constant expression rejected
- invalid condition type rejected

### 51.4 Namespace context

- conditional function declaration
- conditional function definition
- conditional variable declaration
- conditional type alias
- conditional class definition
- conditional enum definition
- conditional template declaration
- conditional namespace definition
- same name in mutually exclusive arms
- duplicate selected declaration rejected

### 51.5 Class and union context

- non-static data member
- static data member
- inline static data member
- member function declaration
- member function definition
- static member function
- constructor
- destructor
- conversion function
- defaulted function
- deleted function
- nested class
- nested enum
- nested union
- type alias
- alias template
- member template
- nested class template
- `static_assert`

### 51.6 Enum context

- selected enumerator exists
- non-selected enumerator does not exist
- implicit enumerator value assignment with selected entries
- implicit enumerator value assignment with non-selected entries removed
- duplicate selected enumerator rejected
- duplicate non-selected enumerator ignored
- context-invalid non-enumerator rejected
- separator handling with selected arm
- separator handling with non-selected arm
- empty selected arm
- empty non-selected arm

### 51.7 Block context

- conditional local variable
- conditional local type alias
- conditional local class
- conditional local enum
- conditional static local
- selected declaration visible after generalized `if constexpr`
- non-selected declaration not visible
- selected declaration has normal initialization and lifetime
- selected statements are emitted
- non-selected statements are not emitted
- control-flow statements valid where context permits
- labels valid where context permits
- selected labels visible to valid `goto`
- non-selected labels unavailable

### 51.8 Restricted constructs

- access label inside class arm rejected
- friend declaration inside class arm rejected
- namespace definition inside block arm rejected
- statement inside class arm rejected
- declaration invalid for enum body rejected
- declaration invalid for namespace body rejected

### 51.9 Non-selected arms

- non-selected declaration does not affect lookup
- non-selected declaration does not affect layout
- non-selected enumerator does not exist
- non-selected declaration does not appear in overload set
- non-selected statement does not emit code
- non-selected declaration does not generate symbols
- non-selected entry can be used for helpful diagnostics
- invalid non-selected entry is still rejected
- non-selected `static_assert(false)` does not fire

### 51.10 Selected arms

- selected declaration participates in lookup
- selected declaration affects layout where applicable
- selected enumerator exists
- selected declaration appears in overload set
- selected statement emits code
- selected declaration generates symbols where applicable
- selected declaration affects type properties where applicable

### 51.11 Templates

- class template specialization selects different members
- enum template specialization selects different enumerators
- function template instantiation selects different block entries
- explicit specialization supports generalized `if constexpr`
- partial specialization supports generalized `if constexpr`
- explicit instantiation uses selected entries
- out-of-class definition for selected member
- out-of-class definition for non-selected member rejected
- dependent nested generalized `if constexpr`
- dependent condition with `requires` where supported

### 51.12 Tooling and serialization

- AST dump shows generalized `if constexpr` node
- AST dump shows selected and non-selected arms
- source locations are preserved
- tooling can inspect generalized `if constexpr` structure
- precompiled headers preserve generalized `if constexpr` structure
- modules serialize generalized `if constexpr` nodes
- deserialization supports later arm selection for dependent conditions

---

## 52. Implementation notes

This section is non-normative.

An implementation will likely need to represent generalized `if constexpr` explicitly in the AST while also exposing selected entries as active entries in the relevant semantic context.

Important implementation requirements include:

- parse `if constexpr` in permitted contexts
- implement transparent selected-arm contribution
- reject plain `if` in contexts where only generalized `if constexpr` is valid
- require `constexpr` on each `else if` branch
- preserve source locations for the full chain
- store each arm's condition
- store each arm's entries
- support dependent conditions
- validate non-selected arms without inserting them into the active context
- retain non-selected entries for diagnostics and tooling
- select only the chosen arm for each specialization or instantiation
- ensure non-selected arms do not affect ordinary lookup
- ensure selected entries participate in lookup
- ensure selected entries participate in layout where applicable
- ensure selected entries participate in enumerator lists where applicable
- ensure selected entries participate in overload resolution where applicable
- ensure selected entries participate in initialization and lifetime where applicable
- ensure selected entries affect type properties where applicable
- ensure non-selected entries do not generate symbols
- ensure non-selected statements do not emit code
- ensure diagnostics can point to both use sites and relevant generalized `if constexpr` arms
- ensure AST traversal can observe source-level generalized `if constexpr` structure
- ensure serialization and deserialization preserve generalized `if constexpr` nodes
- ensure pretty-printing and AST dumping represent generalized `if constexpr` chains clearly

The implementation should preserve both:

1. the source-level generalized `if constexpr` structure, and
2. the semantic active entries for each specialization or instantiation.

---

## 53. Design summary

Generalized `if constexpr` follows these rules:

1. `if constexpr` may appear in supported syntactic contexts beyond standard statement contexts.
2. In C++MG mode, statement-context `if constexpr` also follows the generalized transparent-arm model.
3. Each arm contains entries valid for the immediately enclosing context.
4. The selected arm is transparent.
5. The selected arm contributes its contents as though written directly at the location of the `if constexpr`.
6. Non-selected arms contribute no active entries.
7. At namespace scope, selected namespace declarations become namespace declarations.
8. At class, struct, and union scope, selected member declarations become members.
9. At enum scope, selected enumerators become enumerators.
10. At block scope, selected statements and declarations become part of the enclosing statement sequence.
11. Selected block-scope declarations are visible after the generalized `if constexpr` when they would be visible if written directly at that location.
12. Every `else if` in the chain must be `else if constexpr`.
13. Conditions must be compile-time conditions.
14. Conditions may be dependent.
15. Conditions may use `requires` expressions where supported by the selected C++ standard mode.
16. Non-selected arms are still parsed.
17. Non-selected arms must still contain context-valid code or entries.
18. Non-selected entries may be retained for diagnostics and tooling.
19. Selected entries preserve ordinary source order.
20. Nested selected generalized `if constexpr` constructs are flattened recursively where the enclosing context is a list-like context.
21. Statements are allowed inside arms where statements are valid, such as function bodies.
22. Statements are not allowed inside arms where statements are not valid, such as class bodies, namespace bodies, or enum bodies.
23. Access labels are not allowed inside class, struct, or union arms.
24. Friend declarations are not allowed inside class, struct, or union arms.
25. Selected entries affect lookup, layout, enumerator sets, overload resolution, generated code, lifetime, type properties, and ABI as applicable.
26. Non-selected entries do not affect lookup, layout, enumerator sets, overload resolution, generated code, lifetime, type properties, or ABI.
27. Out-of-class definitions may name only members that exist in the relevant specialization.
28. Explicit instantiation uses the selected entries for the specialization.
29. Tooling should preserve both the source-level generalized `if constexpr` structure and the active semantic entries.
30. Precompiled headers and modules should preserve generalized `if constexpr` AST nodes.

---

## 54. Future extensions

The following are outside the scope of this version.

### 54.1 Friend declarations inside class arms

Friend declarations are banned in this version.

A future revision may define conditional friend injection and lookup behavior.

### 54.2 Conditional base clauses

Generalized `if constexpr` does not conditionally control base-specifier lists.

A future feature may define conditional base clauses.

### 54.3 Attributes on generalized `if constexpr`

Attributes on entries inside selected arms are supported where ordinary C++ supports them.

Attributes on the generalized `if constexpr` construct itself are reserved unless separately specified.

Reserved example:

```cpp
[[some_attribute]]
if constexpr (B) {
  int x;
}
```

### 54.4 Exact tooling API

This specification requires that generalized `if constexpr` structure be represented for tooling, but it does not define exact cursor kinds, AST dump formatting, serialization record names, or source-mapping APIs.

Those details are implementation-defined unless specified separately.
