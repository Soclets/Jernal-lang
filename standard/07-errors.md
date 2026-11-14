# 7. Checks and error messages

## 7.1 When a check happens

A check happens when compiling whenever the compiler can know the answer then, and at runtime otherwise (D8). From the
start, the compiler checks these when compiling:

- what an `if` just checked: inside `if $d != 0:`, dividing by `$d` needs no runtime check;
- loop ranges: in `for $p in range[from: 1, to: $xs.length]:`, `$xs[pos: $p]` is known to be in bounds.

Contracts (`requires`, `ensures`) are checked at runtime.

A runtime check that fails stops with a clear error, never a wrong answer. A runtime check the compiler proves always
passes is dropped (D9). Both depend on the build mode: `FinalPerf` keeps no runtime checks (chapter 10).

## 7.2 What's a check

Checks are bugs in the program's own assumptions: they are `RuntimeError`s, can't be handled, and are prevented up front
instead (D53).

| Check | Example |
|---|---|
| a position outside the list | `$xs[pos: 0]`, `$xs[pos: 99]` |
| dividing by zero | `$a / 0` |
| a false contract | `requires $n at_least 1` |
| a `step_by:` of 0 | a range that never ends |
| a number too big for its type | an `Int` overflowing |
| running out of memory | |

A position that comes from outside, such as user input, can be asked for as a failure instead, with a method like
`$xs.get(pos: $p)` (D53). Its name isn't decided yet.

## 7.3 The message format

Every error has the same layout (D10):

```
CompileTimeError: main.jern:3:16, line 3 column 16
 3 | let $c: List<Int> = $a
   |                     ^^
 what: `$a` can change inside, so handing it off needs `give` or `copy`
 why:  a hand-off says what it does (D7)
```

- The first word is the kind: `CompileTimeError:` (the compiler refused the program), `RuntimeError:` (a check failed
  while running), `warning:`, `NotDesignedYet:` (not decided), `NotBuiltYet:` (decided, not built), or `CompilerBug:`
  (7.5).
- The place is written twice: `file:line:col` for tools, with the column in UTF-8 bytes, then `line N column M` for
  people, with the column in grapheme clusters. A runtime error that no code line caused has no place line.
- The `^` run sits under exactly the part in question.
- Labels, one line each, with code in backticks:
  - `what:` says what's wrong. It's always there, unless `fix:` replaces it.
  - `why:` is always there. It names the rule, cites its decision number and links the standard's section.
  - `when:` gives the values that break it, where known.
  - `because:` shows earlier lines that led here, only when the compiler knows they did.
  - `fix:` appears only when there's exactly one possible fix, and replaces `what:`. No "did you mean" guesses.
- Wording is only what's certain, neutral and about the program: no "you", no apologies. It uses Jernal's own words, and
  never says which implementation printed it.
- A runtime error has no stack trace, only the `because:` steps the compiler knows. Before the message, buffered output
  is flushed.

## 7.4 Every error at once

Every error is shown, not just the first (D10, D13). Knock-on errors are found by applying the first error's single fix
in memory and checking again; whatever disappears gets a `because:` pointing back, such as "with `total` here, this
error goes away". For errors with no single fix:

- Only the broken statement is skipped, and checking carries on with the next one.
- A skipped `let` or `decl` still creates its variable, with the type it wrote, or an unknown type if it wrote none.
- A line that opens a block, with no single fix, skips only that line. The body is still checked, with the broken part
  treated as unknown, and the named `end` says where the block stops.
- A broken function header still creates the function; whatever is broken counts as unknown.
- Nothing is guessed: an error that only happens because something is unknown isn't shown.

## 7.5 When the compiler itself fails

```
CompilerBug: the compiler itself failed
 what: linking: undefined symbol `memset`
 why:  this is a bug in the compiler, not in the program
 fix:  report it at https://github.com/Soclets/Jernal-lang/issues with the program that caused it
```

Only `what:` changes; `why:` and `fix:` are always the same (D12). A bad program never crashes the compiler (rule 13).

## 7.6 Exit codes

Each kind has its own exit code, counting down from 122 (D11):

| Code | Meaning |
|---|---|
| `0` | ran fine |
| `122` | `RuntimeError` |
| `121` | `CompileTimeError` |
| `120` | `NotDesignedYet` |
| `119` | `NotBuiltYet` |
| `118` | `CompilerBug` |

Programs use 1 to 117 for their own reasons; `exit()` refuses 118 to 122.
