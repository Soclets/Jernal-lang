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

## Built (192 tests passing)

- Manifest: `name`, `ver`, `need std 2026y-11m-14d`, `kind tests`, `use` blocks for a file and `all` (D60, D114,
  D115); other packages and dates and scoped lines give NotBuiltYet; `rule` lines give NotDesignedYet.
- Chapter 1: lines, brackets across lines, comments and comment blocks, `<`/`>` spacing, refused spellings with fixes,
  named closers, strings and escapes, control characters refused (D139).
- Chapter 2: every integer width (Int64 or Z), overflow checks, `.wrap`/`.saturate`, `div.*`, `mod.*`, `f64`/`f32`/
  `f16`/`bf16` (correctly rounded, `numbers.ml`) and their text, `Rational`, `Decimal` (decimal128, `decimal.ml`),
  `Bool`, `String`, lists, maps (D138, D141), structs with defaults, tagged unions, `type.alias`, `type.new`,
  `fam.type.new`, bounds and `Array` (D135, `fits.ml`), conversions with `as` (D91).
- Chapter 3: `let`, `mut`, `decl`/`assign` on every path, `shadow`, `change`, `give` (each branch its own path),
  `copy`, top-level `let`, `let baked` worked out when compiling, keeping a parameter needs `copy` (D139).
- Chapter 4: comparisons and chains (D139), logic, joins, indexing, `if`, `match`, the case test (unions and bounds),
  `while`, `for`, named `break`, `at pos`/`at offset`, ranges (a literal one that never ends is refused), `sum`.
- Chapter 5: functions, `return early`, labels, defaults, `requires`, `fn.pure`, `fn.pure.baked`, `fam.fn`, presets,
  methods with `$self`/`mut $self`, dot calls on a family function's first argument, `versions` (D46), generic
  functions, structs and their methods (D103), interfaces, type sets and `satisfies` (D105), `fn.main`, `my::`.
- Chapter 6: `fails`, `fail`, `?`, `??`, `?? ignore`, `otherwise` with `instead`, `fam.failure` written in full (D140),
  `fam.handler` with `*`, `match ... with`, for-line handling (D134), unhandled failures crash (D137).
- Chapter 7: the message format, knock-on errors with `because:` (each fix is an in-memory edit, D13), recovery of
  refused lines and broken function headers, exit codes, errors in source order with a blank line between (D139).
- Chapter 8: `struct.must_give` given exactly once on every path, before every way out, never copied (D51, D52).
- Chapter 9: `pub` on functions, types and fields across files (D106), `use` (D60, D114, D115).
- Chapter 13: `println`, `read_line`, `read_all`, `lines`, `args`, `program_path` (the package folder, D139), `exit`
  (0 to 117), list, string and map methods; `.raw()` gives NotDesignedYet.

## Next

- Tests for multi-file packages, `pub` and `use` errors, once package tests are decided (asked).
- Whatever Tankun decides on the open questions below.
- Out of scope: units (after v1), quills and Dialects, threads, shields, every build mode but `Interp`.

## Tools

- `oracle/tools/robustness.py <scratch>`: runs every test changed in small ways (cut short, lines and words removed)
  and reports any crash of the oracle (rule 13). Last run: 15,196 programs, no crashes.

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

- Package tests: a subfolder of `tests/` with its own `Journey.siml` is one test, with `<folder>.out/.err/.exit`.
- Float and Decimal dividing by zero: IEEE (inf, NaN) or a check? [IEEE]
- `for` over a list changed inside the loop [the items it had when the loop started]; `for` over `Map.insertion`/
  `Map.sorted` [NotDesignedYet]; `remove(key:)` with a missing key [a check]; Decimal text `1.10` [`1.1`]; converting
  Float or Rational into Decimal [NotDesignedYet]; a case with no data [`Status.ok[]`; design expects `Status.ok`].

- Exactly what "known when compiling" is (D8, D135): proposed the baked expressions; the oracle uses literals and baked.
- A literal argument that fits more than one version (D46): the oracle refuses the call (choice b, kept for now).
- Where `Equatable`/`Ordered` come from, and how a type defines `==` and `<` (D105): the oracle uses program-declared
  interfaces only, built-in types satisfy only through a line, and comparing structs is NotDesignedYet.
