# Jernal — design decisions

Tankun decides; Jernal Design Claude proposes and records. Each entry says what was chosen and whose idea it was.
Numbers are permanent, so a decision is never renumbered. A changed decision gets a new entry that says which one it
replaces.

## Decided

**D1. Session rules, printed by a hook.** `RULES.md` holds the rules for every Jernal session, and a `SessionStart` hook
in `.claude/settings.json` prints it at startup, resume, clear and after compaction. The setup and most rules come from
Cyborg's, as its design session described them on 2026-11-13. Claude drafted the rules and the owner shaped them: the
commit, implementation and cores rules were added at the owner's request ("Where's the commit rule, impl rule, and core
count rule?"); owner quotes in commits are exact ("owner quotes shouldn't be inexact, they should be exact. If too long,
in commit say `(owner: too long)`"); the language-independent rules from Cyborg were all added ("all of the first
group"); and the result was adopted ("yea"). (Owner, 2026-11-13)

**D2. Commit and push automatically.** Sessions commit and push without asking, as Cyborg's do. Placeholders are
allowed, and are marked as placeholders. Claude mentioned Cyborg's rule; the owner chose: "Use that rule too".
(Owner, 2026-11-13)

**D3. Public on Soclets, licensed like Cyborg.** The repository is public at `Soclets/Jernal-lang`. Code is under
Apache-2.0 WITH LLVM-exception, in `LICENSE`: the stock Apache 2.0 text with LLVM's exception appended, so programs
compiled with Jernal owe nothing. The repo's Markdown is under CC BY 4.0, in `LICENSE-CC-BY-4.0`. There is no copyright
line, no NOTICE file and no SPDX headers, and the README has a Licences section. This is Cyborg's licensing (its D262),
as Cyborg's design session described it on 2026-11-13; both files went in before the first public push. The owner said:
"Pub on Soclets as `Jernal-lang`. Same licensing as Cyborg (ask session, don't look)". (Owner, 2026-11-13)

**D4. A fix that changes a test's expected output asks first.** Rule 7 (fix what needs no question) gains the clause
from Cyborg's rule 18: a fix that would change what a test expects goes to Tankun through Jernal Design Claude first,
like one that needs a design choice. Otherwise a session could change a test to match its own bug. The owner asked "Is
there auto fix bugs rule yet?"; Claude pointed out the clause was missing; the owner chose: "yea". (Owner, 2026-11-13)

**D5. `let`, `var` and `let baked`.** `let` declares a variable that can't change, and `var` one that can. `let baked`
declares one whose value must be known when compiling. "baked" is Jernal's word for compile-time things.

```
let $x: Int = 1000
var $total: Int = 0
let baked $limit: Int = 100
```

Claude asked what the difference between `let` and `var` is; the owner said: "let can't change, var can, `let baked`
is must be known when compiling. "baked" is the compile time stuff word". (Owner, 2026-11-13)

**D6. `let` freezes the inside too.** A `let` value can't be reassigned, and nothing inside it can change either: a
`let` list never gains or loses an item. This is how `let` works in maths, where a value never changes and only which
name points at which value does. The owner asked: "math's `let` doesn't let insides change, right? And I mean, I'm
leaning there too"; Claude confirmed and summarized; the owner chose: "yea, record them". (Owner, 2026-11-13)

**D7. `Give` and `Copy`, for clarity, not full ownership.** The garbage collector does all the memory work. Ownership
words exist only so a reader can see when two names could share something that changes.

- Handing off something whose inside can change, such as a `var` list or object, says `Give` or `Copy`. `Give $a`
  moves it to the new name and retires `$a`, copying nothing. `Copy $a` makes a separate one, and both stay usable.
- Plain values need no word: numbers, `bool`, strings, and anything frozen.
- There is no `Lend`, no lifetimes, no borrow checker and no `must_Give`. A missing word gives the error "say `Give` or
  `Copy`".
- Using a name after it was given is refused when compiling. A name that might have been given, such as one given
  inside an `if` or a loop, counts as given.
- `let $b = Give $a` freezes the list without copying it, since nobody is left who could change it.

```
var $a: List = [1, 2, 3]
let $b: List = Copy $a     // ok: a separate list
let $c: List = $a          // refused: say Give or Copy
let $d: List = Give $a     // ok: $a is retired
let $n: Int = $x           // ok: plain values need no word
```

Claude first proposed copying on every assignment, as Swift does; the owner said: "I'm used to ownership, so that's
weird." Claude then proposed Cyborg's words; the owner said: "Like, maybe just for clarity, and not full-on
Ownership", asked "Compile time or runtime check?", and chose: "yea, record them". (Owner, 2026-11-13)

**D8. Compile time when possible, runtime when too hard.** A check happens when compiling whenever it can, and at
runtime when that's too hard. From the start, the compiler checks these when compiling:

- What an `if` just checked: inside `if $d != 0:`, dividing by `$d` needs no runtime check.
- Loop ranges: in `for $i in 0..$list.length:`, `$list[$i]` is known to be in bounds.

Contracts, such as `requires $n >= 0`, are checked at runtime: proving them when compiling needs a prover like SPARK's
or Verus, which is too heavy.

The owner sketched: "compile time when possible, runtime when too hard". Claude listed three checks that are possible
but take work; the owner chose: "Ah, we could do 1 & 2 at start in compile, 3 is too heavy so runtime." (Owner,
2026-11-13)

**D9. Runtime checks never give a wrong answer, and proven ones are dropped.** Adds to D8. A runtime check that fails
stops with a clear error, never a wrong answer. A runtime check the compiler proves always passes is dropped, so safety
costs nothing where the compiler can see it's safe. Claude proposed both; the owner chose: "added". (Owner, 2026-11-13)

**D10. Error messages: Cyborg's format, with Jernal's own kinds.** The format is Cyborg's (its D16, which came from
Radium), as Cyborg's design session described it on 2026-11-13, with two changes: the kinds are named plainly, and
`why:` links the spec as well as the decision. The file name below is a placeholder.

```
CompileTimeError: main.jernal:3:16, line 3 column 16
 3 | let $c: List = $a
   |                ^^
 what: `$a` can change inside, so handing it off needs `Give` or `Copy`
 why:  a hand-off says what it does (D7)
```

- **The first word is the kind:** `CompileTimeError:` (the compiler refused the program), `RuntimeError:` (a check
  failed while running), `warning:`, `NotDesignedYet:` (not decided) and `NotBuiltYet:` (decided, not built). Cyborg's
  `unproven:` is dropped, since Jernal has no prover (D8).
- **The place is written twice:** `file:line:col` for tools, with the column in UTF-8 bytes, then `line N column M` for
  people, with the column in grapheme clusters. A runtime error that no code line caused has no place line.
- **The `^` run sits under exactly the part in question**, not the whole line.
- **Labels**, one line each, with code in backticks:
  - `what:` says what's wrong. It's always there, unless `fix:` replaces it.
  - `why:` is always there. It names the rule, cites its decision number and links the spec section.
  - `when:` gives the values that break it, where known.
  - `because:` shows earlier lines that led here, only when the compiler knows they did.
  - `fix:` appears only when there's exactly one possible fix, and replaces `what:`. No "did you mean" guesses.
- **Every error is shown, not just the first.** Knock-on errors are found by applying the first error's fix in memory
  and checking again; whatever disappears was caused by it and gets a `because:` pointing back. After an error,
  checking skips only that statement.
- **Runtime errors** have no stack trace, only the `because:` steps the compiler knows. Before the message, buffered
  output nobody is using is flushed, so the last thing printed shows.
- **Wording:** only what's certain. Neutral and about the program: no "you", no apologies. Jernal's own words. It never
  says which implementation printed it.

Still open, which Cyborg's design session advised deciding early: exit codes (since decided in D11), the wording when
the compiler itself fails, and what happens after an error on a line that opens a block, such as an `if`.

Claude proposed Cyborg's format with `unproven:` dropped and a spec link in `why:`; the owner said: "Seems good, before
you record. Maybe change `refused` and `check failed` to be more straightforward, `CompileTimeError` and
`RuntimeError`?" Claude worried that "compile time" competes with "baked" (D5); the owner chose: "the baked worry, just
use CompileTimeError and RuntimeError". (Owner, 2026-11-13)

**D11. Exit codes count down from 122.** Each kind of error has its own exit code, so a tool can tell what happened
from the number alone:

| Code | Meaning |
|---|---|
| `0` | ran fine |
| `122` | `RuntimeError` |
| `121` | `CompileTimeError` |
| `120` | `NotDesignedYet` |
| `119` | `NotBuiltYet` |
| `118` | the compiler itself failed |

The codes sit near the top of the usable range so that programs keep 1–117 for their own use, and `exit()` refuses
118–122. They start at 122, not 125, because 123–125 are already used by GNU `timeout`, `xargs` and `git bisect run`,
and 126 and up are the shell's.

Claude proposed codes following the usual habits; the owner asked "Is there a standard for this, or nah?", then said "Or
maybe just whatever code, but separate. So the tool could you know? Get it" and "For fun, maybe go from limit? Like
100 something". Claude proposed counting down from 122; the owner chose: "yea". (Owner, 2026-11-13)
