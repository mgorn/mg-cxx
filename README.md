# C++MG
I have been writing C++ for a few years now, and it is easily one of my favorite languages to work with. This is a sentiment shared with many others as this has been THE language to use for so long. Most meaningful software in our daily lives has it's origins in C or C++ code. That being said, there are other languages like Zig that I would say sometimes do things better (and other times do things worse...). I want the best of both, so I am making my own version of C++ for myself.

Come find me on Discord if you want to talk nerd shit like this: https://discord.gg/RM8BVwAfZy

# Features
## `if constexpr` class members
I don't know why this isn't already a language feature, so I'm working on adding this myself. I don't know the process for getting new language features into the C++ standard, but honestly I don't really care. I just want this feature myself, and if you want it too, the code is here.
Anyways, I'm sick and tired of having to do bullshit like this:
```C++
template<bool test>
struct A {};
template<>
struct A<true> {
  int counter = 0;
};

struct B {
  static constexpr bool smth = ...;

  A<smth> v;

  void func() {
    // U need to check "smth" with if constexpr here
    v.counter = 2;
  }
};
```
So instead, with this compiler you can simply do this:
```C++
struct B {
  static constexpr bool smth = ...;
  if constexpr (smth) {
    int counter = 0;
  }

  // This needs to be some template or consteval function! Otherwise you risk the compiler semantically evaluating members that don't exist.
  template<typename T = B>
  void func(const T& b) {
    // if constexpr again because "counter" will only exist then
    if constexpr (T::smth) {
      b.counter = 2;
    }
  }
};
```
You can test for this feature with the `__cxxmg_if_constexpr_member` macro or the `__has_feature(cxxmg_if_constexpr_members)` feature test.
E.g.
```
#ifdef __cxxmg_if_constexpr_member
// if constexpr here
#endif
```
or
```
#if __has_feature(cxxmg_if_constexpr_members)
// if constexpr here
#endif
```

## Changed executable name
I also changed the name of the clang binary to `clang-mg`. This is just so I could have this be distinct from my normal `clang`. I want to be able to install both simultaneously and not have to worry about anything conflicting. Also would make it easier for me to distribute this, I think others could find it useful, and I want to use it for my own open-source projects, which would require me to distribute this so it's not a pain in the ass to compile those.

## cURL Include
You can use a `#curlinclude` directive to have curl download a header into the `.cxxmg/` cache dir & include it like normal.

## Traits
A simpler alternative to C++'s concepts is my trait system. It's not exactly how you'd expect it to be from other languages, but it's simple and allows you to test attributes of structures with ease.
Defining a "trait" would be like defining any `struct` or `class`, but it's just a concept of one and cannot be used like one:
```
// An example structure
struct A {
  int value = 0;
};
struct B {
  bool test = false;
};

// A trait describing a struct/class containing an 'int' named 'value'
trait ValueTrait {
  int value;
};
trait TestTrait {
  bool test;
};
```
We can then use the traits as follows:
```

```

# Building
Managing an actual LLVM fork is quite a task when it's being constantly updated. This repository contains a set of patches that can be applied to the LLVM source code to add each feature.