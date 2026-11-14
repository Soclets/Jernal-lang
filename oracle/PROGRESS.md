# JernOrac progress

JernOrac is the oracle: a plain interpreter for Jernal, written from `standard/` only (D69, D126, rule 18).
This file, the tests in `tests/` and the git log are the oracle session's memory.

## Building and running

```
oracle/build.sh                                   # dune build -j 3, in the opam switch `jernal-oracle`
oracle/_build/default/bin/jernorac.exe run -- a b # jern run --Interp -- a b, from inside a package
oracle/_build/default/bin/jernorac.exe test       # jern test --Interp, from inside tests/
oracle/_build/default/bin/jernorac.exe -C tests test d62_hello_world   # some tests only
```

Setup, done once: `opam init --bare --no-setup`, `opam switch create jernal-oracle ocaml-system`,
`brew install pkgconf`, `opam install --switch=jernal-oracle --assume-depexts zarith uuseg`.
Libraries: zarith (GMP integers and rationals, for wide integers and `Rational`), uuseg (grapheme clusters,
for columns and `len()`).

## Layout

| File | What |
|---|---|
| `src/text.ml`, `src/span.ml` | UTF-8, graphemes, places |
| `src/diagnostic.ml` | the message format of 7.3 and exit codes of 7.6 |
| `src/lexer.ml`, `src/token.ml` | chapter 1: lines, comments, `<` `>` spacing, refused spellings |
| `src/syntax.ml`, `src/parser.ml` | the syntax tree, read a line at a time with the recovery of 7.4 |
| `src/types.ml`, `src/checker.ml` | types and every compile-time check; produces `Checked` |
| `src/checked.ml` | the checked program the interpreter runs |
| `src/value.ml`, `src/interpreter.ml` | values and running, with every runtime check |
| `src/std_library.ml` | std, from chapter 13 (D127) |
| `src/manifest.ml` | reading and checking `Journey.siml` |
| `src/package.ml`, `src/test_runner.ml`, `bin/jernorac.ml` | the commands |

## Built (176 tests passing)

- Manifest: `name`, `ver`, `need std 2026y-11m-14d`, `kind tests`; other packages, dates, `rule`, scopes and
  `use` blocks give NotBuiltYet.
- Chapter 1: lines, brackets across lines, comments and comment blocks, `<`/`>` spacing, refused spellings with fixes,
  named closers, strings and escapes, control characters refused (D139).
- Chapter 2: every integer width (Int64 or Z), overflow checks, `.wrap`/`.saturate`, `div.*`, `mod.*`, `f64`/`f32`/
  `f16`/`bf16` (correctly rounded, `numbers.ml`) and their text, `Rational`, `Decimal` (decimal128, `decimal.ml`),
  `Bool`, `String`, lists, maps (D138, D141), structs with defaults, tagged unions, `type.alias`, `type.new`, bounds
  and `Array` (D135, `fits.ml`), conversions with `as` (D91).
- Chapter 3: `let`, `mut`, `decl`/`assign` on every path, `shadow`, `change`, `give`, `copy`, top-level `let`,
  `let baked` worked out when compiling, keeping a parameter needs `copy` (D139).
- Chapter 4: comparisons and chains (D139), logic, joins, indexing, `if`, `match`, the case test (unions and bounds),
  `while`, `for`, named `break`, `at pos`/`at offset`, ranges, `sum`.
- Chapter 5: functions, `return early`, labels, defaults, `requires`, `fn.pure`, `fn.pure.baked`, `fam.fn`, presets,
  methods with `$self`/`mut $self`, `versions` (D46), generic functions and structs (D103), interfaces, type sets and
  `satisfies` (D105), `fn.main`, `my::`.
- Chapter 6: `fails`, `fail`, `?`, `??`, `?? ignore`, `otherwise` with `instead`, `fam.failure` written in full (D140),
  `fam.handler` with `*`, `match ... with`, for-line handling (D134), unhandled failures crash (D137).
- Chapter 7: the message format, knock-on errors with `because:` (each fix is an in-memory edit, D13), recovery of
  refused lines, exit codes, several errors in source order with a blank line between (D139).
- Chapter 13: `println`, `read_line`, `read_all`, `lines`, `args`, `program_path` (the package folder, D139), `exit`
  (0 to 117), list, string and map methods.

## Next

- `pub` on types, fields and family members across files (functions are done, D106); tests for `pub` and `use` errors
  (see open questions).
- Methods on a generic struct, `$x.show()` style calls on a family function's first parameter, units (after v1: NotBuiltYet).
- Shields, quills, threads: out of scope (NotBuiltYet / NotDesignedYet).

## Error wording proposed by the oracle (D137)

Every `what:`/`why:` text in `tests/*.err` is the oracle's proposal until Jernal Design Claude reviews it.

## Choices made without a decision (to confirm)

- A package's `.jern` files are the ones directly in its folder, not in subfolders.
- Tests run with empty standard input and no arguments.
- `$m.remove(key:)` with a missing key is a check, like `$m[key:]`.
- An item or entry (`$xs[pos: 1]`, `$m[key: $k]`) may stand in a join like a field, as D138's example does.
- A literal `Status.ok[]` builds a case with no data; `Status.ok` alone isn't a value.
- A value stored where it can change (`let mut`, `change`, `add`) is copied, so nothing frozen changes through it.

## Open questions (sent to Jernal Design Claude, waiting on Tankun)

- Exactly what "known when compiling" is (D8, D135): proposed the baked expressions; the oracle uses literals and baked.
- A literal argument that fits more than one version (D46): the oracle refuses the call (choice b, kept for now).
- Where `Equatable`/`Ordered` come from, and how a type defines `==` and `<` (D105): the oracle uses program-declared
  interfaces only, built-in types satisfy only through a line, and comparing structs is NotDesignedYet.
