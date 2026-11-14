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
- Lexer: everything in chapter 1, including comment blocks and the `<`/`>` spacing rule with its fix.
- Hello World (d62).

## Next

Chapter by chapter, tests first: integers and arithmetic (2.1), floats as text (2.1a), Bool, strings and joins,
lists and maps, structs, unions, variables (3), control flow (4), functions (5), failures (6), every error of 7.

## Error wording proposed by the oracle (D137)

Every `what:`/`why:` text is the oracle's proposal until Jernal Design Claude reviews it. Tests that record them:
none reviewed yet.

## Choices made without a decision (to confirm)

- Between two messages on stderr, one blank line.
- When several errors stop a program, the exit code is the first one's, in the order printed (by file, line, column;
  errors with no place last).
- A package's `.jern` files are the ones directly in its folder, not in subfolders.
- Tests run with empty standard input and no arguments.

## Open questions (sent to Jernal Design Claude)

(none open)
