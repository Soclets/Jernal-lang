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
| `src/numbers.ml`, `src/decimal.ml` | correctly rounded binary floats; decimal128 |
| `src/fits.ml` | whether a value fits a type's bounds (D135) |
| `src/methods.ml`, `src/std_library.ml` | built-in methods (13.3) and std's functions, from chapter 13 (D127) |
| `src/source.ml` | quoting the program in messages |
| `src/manifest.ml` | reading and checking `Journey.siml` |
| `src/package.ml`, `src/test_runner.ml`, `bin/jernorac.ml` | the commands |

## Built (240 tests passing)

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
  functions, structs, unions and methods (D103), interfaces, type sets and `satisfies` (D105), `fn.main`, `my::`.
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
- Bounds written as a `let baked` value work (D135), top-level or earlier in the same function; one whose value
  calls a function that isn't checked yet gives NotBuiltYet, since types are resolved before it's worked out.
- Whatever Tankun decides on the open questions below.
- Out of scope: units (after v1), quills and Dialects, threads, shields, every build mode but `Interp`.

## Tools

- `oracle/tools/robustness.py <scratch>`: runs every test changed in small ways (cut short, lines removed, repeated or
  swapped, words removed or shortened, random tokens put in)
  and reports any crash of the oracle (rule 13). Last run: 45,581 programs (20,000 with random tokens put in), no crashes.
- `oracle/tools/crosscheck.py <scratch>`: checks float text (D119), Decimal (D83), integer division and remainders
  (D85, D88), Rational (D139) and f32/f16 sums (D93) against Python's own implementations, about 300 random cases
  each, float sums against math.fsum (D38), the rounding words of `as` (D91), and wrapping and saturating (D92). Last run: 2,494 cases, no differences.

## Error wording proposed by the oracle (D137)

Every `what:`/`why:` text in `tests/*.err` is the oracle's proposal until Jernal Design Claude reviews it.
`python3 -I oracle/tools/wording.py` lists each distinct text once (173 so far), with a test that shows it.

## Choices made without a decision (to confirm)

- A package's `.jern` files are the ones directly in its folder, not in subfolders.
- Tests run with empty standard input and no arguments, and a test running longer than 60 seconds is stopped and
  fails (`JERNORAC_TEST_SECONDS` changes the limit, for checking the runner itself).
- `$m.remove(key:)` with a missing key is a check, like `$m[key:]`.
- An `assign` inside a loop is refused, even when a `break` follows it (to ask: how precise "once on each path" is).
- A number literal with nowhere to land (`println(5 as String)`, `if 3 < 4:`) is an `Int`; a literal with a `.` there
  is refused, since it has no type.
- A map literal that gives one key twice keeps the last value.
- Arguments, operands and fields are worked out left to right.
- `-0.0` as text is `-0`.
- Graphemes (for `len()` and the people's column) follow Unicode 18.0.0 (uuseg/uucp 18.0.0), until D130's
  "which Unicode version each std date follows" is decided.
- An item or entry (`$xs[pos: 1]`, `$m[key: $k]`) may stand in a join like a field, as D138's example does.
- A literal `Status.ok[]` builds a case with no data; `Status.ok` alone isn't a value.
- A value stored where it can change (`let mut`, `change`, `add`) is copied, so nothing frozen changes through it.

## Next batch for Jernal Design Claude (send about hourly)

(empty; the last batch went at 13:40)

## Open questions (sent to Jernal Design Claude, waiting on Tankun)

- How tightly `??`, `?`, `otherwise` and `as` bind next to D90's operators: `$m.get(key: $k) ?? 0 + 1` [`??` loosest].
- A number literal with nowhere to land, as in `println(5 as String)` [an `Int`; `2.5 as String` is refused].
- A map literal giving one key twice, `["a" => 1, "a" => 2]` [the last one wins; refusing it is the other option].
- Order of evaluation: arguments, operands and struct fields [left to right, as written].
- How precise "can reach its end without returning" is (D26): a `while true:` with a `return` inside, or a call to
  `exit()` last [both are refused: only `return`, `fail`, and `if`/`else` or `match` where every branch ends, count].
- Whether a manifest without `name` or `ver` is refused (9.1) [not refused]; and whether a `use` block for a file
  that isn't in the package is refused [not refused].
- A handler used at a call that can't raise one of its arms' failures (D49: "one handler may cover several failure
  families"): is that arm allowed there? [refused, as an inline arm would be]
- 4.3: an operator inside a join is refused "with a `fix:` that names a step first", but the step needs a name the
  writer chooses, so it isn't one fix. What should the line show? [a `what:` saying a named step is needed]
- The exact list of keywords, since `my::` depends on it (D63). [the oracle's list is in `oracle/src/parser.ml`,
  `keywords`; `range`, `pos`, `offset`, `from`, `to`, `before`, `step_by`, `key`, `self` and `Any` aren't in it]

- Package tests: a subfolder of `tests/` with its own `Journey.siml` is one test, with `<folder>.out/.err/.exit`.
- A `.in` file beside a test as its standard input.
- An `assign` inside a loop followed by `break` (runs once): allowed? [refused]
- Float and Decimal dividing by zero: IEEE (inf, NaN) or a check? [IEEE] Tests that lean on it:
  `d139_nan_and_infinity_as_text`, `d82_negative_zero`, `d83_decimal_infinity_is_ordered`.
- `for` over a list changed inside the loop [the items it had when the loop started]; `for` over `Map.insertion`/
  `Map.sorted` [NotDesignedYet]; `remove(key:)` with a missing key [a check]; Decimal text `1.10` [`1.1`]; converting
  Float or Rational into Decimal [NotDesignedYet]; a case with no data [`Status.ok[]`; design expects `Status.ok`].
- Exactly what "known when compiling" is (D8, D135): proposed the baked expressions; the oracle uses literals and baked.
- A literal argument that fits more than one version (D46): the oracle refuses the call (choice b, kept for now).
- Where `Equatable`/`Ordered` come from, and how a type defines `==` and `<` (D105): the oracle uses program-declared
  interfaces only, built-in types satisfy only through a line, and comparing structs is NotDesignedYet.
