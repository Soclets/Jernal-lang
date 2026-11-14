# 11. Shields and quills

## 11.1 What needs a shield

A shield is where code the compiler can't check lives (D79). Everything outside a shield stays fully checked.

| Needs a shield | Example |
|---|---|
| calling foreign code | a C library's function, a raw system call |
| raw pointers | making one, reading or writing through one, pointer arithmetic |
| inline foreign code | `inline.llvm_ir:`, inline assembly |
| reinterpreting memory | treating bytes as another type, C's untagged unions |
| memory outside the GC | manual `malloc`/`free`-style memory |
| handing a GC object to the outside | passing a list's buffer to C |
| a quill's unchecked LLVM IR | counts as shield code automatically |

These don't: `FinalPerf` dropping checks, a quill producing Jernal code, files, network, the clock and the environment,
and `give`, `copy`, `must_give` and `mut`.

## 11.2 How a shield is written

A shield is a named block. Its body starts with `reason`, then `pin` for each GC object handed to the outside, then the
code (D80).

```
shield read_header:
    reason "libpng's C API takes a raw buffer"
    pin $buffer
    let $ptr: Ptr<u8> = $buffer.raw_address()
    let $status: i32 = png_read($ptr, $buffer.length)
end shield read_header
```

- A pinned object isn't moved or freed by the GC until the shield's `end`. Handing out an object that isn't pinned is
  refused.
- The build report lists every shield, with its reason, and any quill's unchecked IR.
- Only what a shield gives back has to be valid Jernal.

## 11.3 Books and quills

A package can have a book, its library half, a quill, its compiler half, or both, under one name and version (D77).

A quill is a compiler extension: a native library (`.dylib`, `.so`, `.dll`) that JernComp loads while compiling. It's
trusted when the manifest lists it, with no sandbox, and none is privileged: Jernal's own extensions plug in the same
way.

A quill can:

- read the whole checked program;
- add errors and warnings, which only make programs stricter;
- define what its own items mean;
- produce Jernal code, checked like hand-written code, or LLVM IR, which is unchecked and listed in the build report;
- prove checks can't fail, so they're dropped, except in `Working`.

A quill can never change what code that isn't its own means.

Quills have no marker (D78). Their names are ordinary names, and a clash is an error. Their syntax uses only shapes
Jernal already has: names (calls, types, narrowings), blocks in the `word ...:` / `end word` shape, and raw code in
another language inside an `inline.something:` block, which tools leave alone.

```
let $price: Float = round.half_even($raw)
kernel add_all[$xs: List<Float>]:
    ...
end kernel add_all
inline.llvm_ir:
    %sum = add i64 %a, %b
end inline.llvm_ir
spawn(on: $pool, run: sum($xs))
```

## 11.4 Dialects

A Dialect is a compiler forked from JernComp, for changing what plain code means (D77). It doesn't have to follow any
rules. Every manifest says which one it uses, and plain Jernal can't use a package written in a Dialect.
