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

## Built

- Manifest: `name`, `ver`, `need std 2026y-11m-14d`, `kind tests`; other packages, dates, `rule`, scopes and
  `use` blocks give NotBuiltYet.
- Chapter 1: lines, brackets across lines, comments and comment blocks, `<`/`>` spacing, refused spellings with fixes,
  named closers, strings and escapes, control characters refused.
- Chapter 2: `Int` and every integer width (Int64 or Z), overflow checks, `.wrap`/`.saturate`, `div.*`, `mod.*`,
  `f64` maths and its text (shortest, `~`, `as.stored`, NaN/inf), `Rational`, `Bool`, `String`, lists, maps (D138),
  structs with defaults, tagged unions, `type.alias`, `type.new`.
- Chapter 3: `let`, `mut`, `decl`/`assign` on every path, `shadow`, `change`, `give`, `copy`, top-level `let`.
- Chapter 4: comparisons and chains (D139), logic, joins, indexing, `if`, `match`, the case test, `while`, `for`, named
  `break`, `at pos`/`at offset`, ranges, `sum`.
- Chapter 5: functions, `return early`, labels, defaults, `requires`, `fn.pure`, `fam.fn`, presets, methods with
  `$self`/`mut $self`, `fn.main`, `my::`.
- Chapter 7: the message format, knock-on errors with `because:` (each fix is an in-memory edit, D13), recovery of
  refused lines, exit codes.
- Chapter 13: `println`, `read_line`, `read_all`, `lines`, `args`, `program_path`, `exit`, list, string and map methods.

## Next

- Chapter 6: `fails`, `fail`, `?`, `otherwise`, handler families, `match ... with`, failures from `for` lines.
- Conversions with `as` between number types (D91), `f32`/`f16`/`bf16`, `Decimal` (decimal128).
- Bounds (D135), `Array`, generics, interfaces, `versions`, `let baked`, `fn.pure.baked`, `pub` across files.

## Error wording proposed by the oracle (D137)

Every `what:`/`why:` text in `tests/*.err` is the oracle's proposal until Jernal Design Claude reviews it.

## Choices made without a decision (to confirm)

- A package's `.jern` files are the ones directly in its folder, not in subfolders.
- Tests run with empty standard input and no arguments.
- `$m.remove(key:)` with a missing key is a check, like `$m[key:]`.
- An item or entry (`$xs[pos: 1]`, `$m[key: $k]`) may stand in a join like a field, as D138's example does.
- A literal `Status.ok[]` builds a case with no data; `Status.ok` alone isn't a value.
- A value stored where it can change (`let mut`, `change`, `add`) is copied, so nothing frozen changes through it.

## Open questions (sent to Jernal Design Claude)

- The name of `get`'s failure on a missing key (D138): NotDesignedYet when it crashes.
