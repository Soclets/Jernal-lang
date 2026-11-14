# 10. Tools and build modes

## 10.1 The tools

| Name | What it is |
|---|---|
| JernComp | the compiler, in Rust, driving LLVM through `inkwell`, through `llvm-sys` where `inkwell` falls short, and through small C++ pieces where neither reaches (D65, D74) |
| JernOrac | the oracle, in OCaml (D69, D73, D75) |
| JernGC | the garbage collector (chapter 8, D74) |
| Journey | the package manager, in Go: resolves versions, downloads in parallel, hashes, writes `Journey.lock`; it gets the checked manifest from `jern`, which owns reading siml and its errors (D76, D117) |
| `jern` | the command (D74) |

Jernal files end in `.jern` (D74).

```
jern <comp or run or test> --<mode> <-- <arguments>, only for run>
jern comp --FinalSafe       // compiles
jern run --FinalSafe        // compiles, then runs
jern run --Interp           // runs on the oracle
```

Every command names its build mode; there is no default (D72). `jern` works on the package whose `Journey.siml` is in
the current folder or the nearest one above it, and no file is named (D121). Everything after `--` goes to the
program's `args()`. `jern comp --Interp` is refused, with `fix: jern run --Interp`.

```
jern run --Working -- Tankun
```

## 10.1a Tests

A folder whose `Journey.siml` says `kind tests` treats each `.jern` file as its own program (D122). Next to each test,
`.out` holds the expected standard output, `.err` the expected error output, and `.exit` the expected exit code when it
isn't 0; a missing file means nothing is expected, and results are compared byte for byte. Tests are named after their
decision. `jern test --Interp` and `jern test --Working` run them all and compare.

## 10.2 The oracle

JernOrac is a plain interpreter written straight from this standard (D69). It never optimizes and never drops a check,
even one the compiler proves always passes, so it's the safest way to run a program and the slowest. JernComp must give
byte-for-byte the same output as JernOrac on every test and generated program; where they differ, this standard decides
which is wrong. Neither is written from the other's source.

JernOrac is built by Jernal Oracle Claude, in `oracle/`, with the tests in `tests/` (D126). JernOrac uses OCaml's own
garbage collector, not JernGC, and holds Jernal's integers as `Int64`, never OCaml's 63-bit
`int` (D73). Comparing compiled programs against it also tests JernGC, together with `Working`'s torture option.

## 10.3 Build modes

| Mode | What it's for | In v1 |
|---|---|---|
| `Interp` | runs on JernOrac, with no compiling | yes |
| `Working` | everyday development: the optimization level is chosen, every check stays | yes |
| `FinalSafe` | release: fully optimized, keeps every check it can't prove away | yes |
| `FinalPerf` | release: fully optimized, keeps no runtime checks | yes |
| `FinalQuick` | fast compiling, like Go; needs a second backend such as Cranelift | later |
| `UB++` | drops contracts and bounds checks, and anything wrong is undefined behaviour | later |

(D70)

## 10.4 `FinalPerf`

`FinalPerf` assumes the program has been tested (D71). The "never a wrong answer" of 7.1 doesn't hold in it.

| What goes wrong | `FinalSafe` | `FinalPerf` |
|---|---|---|
| overflow on `+`, `-` or `x` | crash | wraps |
| a position out of bounds, dividing by zero, `step_by: 0` | crash | undefined behaviour |
| a false contract | crash | undefined behaviour; the optimizer may treat it as true |
| a failure nobody handled | crash | crash |
| a compile-time rule broken | refused | refused |
