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
the compiler itself fails (since decided in D12), and what happens after an error on a line that opens a block, such
as an `if` (since decided in D13).

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

**D12. `CompilerBug:` when the compiler itself fails.** The message uses D10's layout, with the kind `CompilerBug:` and
no place line, since no line of the program caused it. Only `what:` changes: it gives the compiler's internal detail.
`why:` and `fix:` are always the same. It exits with `118` (D11).

```
CompilerBug: the compiler itself failed
 what: linking: undefined symbol `memset`
 why:  this is a bug in the compiler, not in the program
 fix:  report it at https://github.com/Soclets/Jernal-lang/issues with the program that caused it
```

Claude proposed it; the owner chose: "yea". (Owner, 2026-11-13)

**D13. Carrying on after an error.** Builds on D10's "every error is shown", which is Cyborg's D207: the first error's
single fix is applied in memory and the program is checked again, and any later error that disappears gets a
`because:` pointing back, such as "with `total` here, this error goes away". This is defined, not guessed, so every
implementation prints the same errors. For errors with no single fix:

- **Only the broken statement is skipped**, and checking carries on with the next one (Cyborg's D215).
- **A skipped `let` or `var` still creates its variable**, with the type it wrote, or with an unknown type if it wrote
  none.
- **A line that opens a block, with no single fix, skips only that line.** The block's body is still checked, with the
  broken part treated as unknown: a broken condition means either branch may run, and a broken `for` still creates its
  loop variable, with an unknown range. The named `end` says exactly where the block stops.
- **A broken function header still creates the function.** Whatever is broken in the header counts as unknown.
- **Nothing is guessed:** an error that only happens because something is unknown is not shown.

This closes the case Cyborg's D215 left open, where its oracle stops checking at a broken opening line. Cyborg's design
session explained D207 and D215 on 2026-11-13; the owner had said "I think Cyborg has a technique on this, and it's
pretty cool. Aks". Claude proposed this set; the owner chose: "yea". (Owner, 2026-11-13)

**D14. Emptiness is written bare.** No parameters, no arguments and empty values are written with nothing inside:

```
fn main[]:
let $now: Time = now()
let $name: String = ""
```

There is no `[none]` and no `empty`; the sketch's `empty` is dropped. A writer who wants it to look finished can add a
comment, such as `fn main[]: // none`. The compiler never sees comments, so this changes nothing: a missing parameter
is caught by every call that passes one, and a string left blank by mistake is caught by neither form. This differs
from Cyborg, which writes `[none]` (its D267) and `empty` (its D103), as Cyborg's design session described on
2026-11-13. Which brackets mean what is not decided yet.

Claude proposed Cyborg's `[none]`, `()` and `empty`; the owner said: "Nah, just leave them empty. If you want it to look
finished, just use `//` comment? This is a question. Would it create mistakes?" Claude explained it wouldn't and asked
whether `empty` for values goes too; the owner chose: "drop too". (Owner, 2026-11-13)

**D15. `( )` runs, `[ ]` describes.** A call runs something, with `( )`. A declaration describes what goes in, with
`[ ]`. So a declaration and a call never look alike. This is the core of Cyborg's D23 (from Radium), as Cyborg's design
session described it on 2026-11-13, and the owner's sketch already wrote it this way.

```
fn greet[$name: String]:       // [ ] describes what goes in
greet("Tankun")                // ( ) runs it
```

Not decided yet: grouping in maths, list literals, indexing, and type details.

Claude proposed it; the owner chose: "yea. As for labels, I absolutely love them". (Owner, 2026-11-13)

**D16. The rules hook doesn't print on resume.** Replaces part of D1. The hook prints `RULES.md` at startup, clear and
after compaction, but not on resume: a resumed session gets its old transcript back, rules included, so printing again
only adds a second copy. The owner noticed it after this session resumed: "I think that's wasted tokens, it was already
in your context?"; Claude proposed dropping `resume` from the matcher; the owner chose: "yea". (Owner, 2026-11-13)

**D17. Indexing always says how it counts.** An index has a label: `pos:` counts from 1, and `offset:` counts from 0.
A bare index is refused, so nobody has to remember which way Jernal counts.

```
$xs[pos: 1]       // the 1st item, counting from 1
$xs[offset: 0]    // the same item, counting from 0
$xs[1]            // refused: say pos: or offset:
```

This is Cyborg's labelled indexing (its D23) without units: Cyborg writes `offset.items:`, and units aren't in
Jernal's v1. The owner said "As for labels, I absolutely love them", then "Woah there, you're also using another major
Cyborg feature, checked units in example"; Claude proposed the two labels without units; the owner chose: "yea".
(Owner, 2026-11-13)

**D18. `<` and `>` are both comparisons and type brackets, told apart by spaces.** A comparison has a space on both
sides. Type brackets stick to the name before them. Anything in between is refused, with the one fix shown (D10).

```
$age < 18              // comparison; so are >, <= and >=
List<Int>              // type brackets
List<List<Int>>        // the >> is two closers, never a shift
$age<18                // refused, fix: `$age < 18`
List <Int>             // refused, fix: `List<Int>`
```

Since variables start with `$` and types never do, the compiler never has to guess; the spacing keeps it readable for
people. Cyborg instead keeps `< >` for types only and writes comparisons as `below` and `above`. The owner said: "We
use `<` and `>`, and `<>` brackets. There's a simple solution: space sensitive"; Claude spelled it out; the owner chose:
"yea". (Owner, 2026-11-13)

**D19. No semicolons: one statement, one line.** A line break ends a statement, and there are no semicolons. An
expression never continues onto the next line; a long one is split into named steps. The only exception is inside
brackets: a call, list or declaration may break between its items.

```
let $subtotal: Int = $price * $count
let $total: Int = $subtotal + $shipping

let $user: User = make_user(
    name: "Tankun",
    age: 30,
)
```

Whether a comma after the last item is allowed is not decided yet. Claude proposed no semicolons, with a trailing
operator continuing the line; the owner said "Is cursed, though". Claude proposed a leading operator instead; the owner
asked "Or just one line?". Claude proposed one line, except between items inside brackets; the owner chose: "yup".
(Owner, 2026-11-13)

**D20. Strings are joined side by side, with no interpolation.** Writing values next to each other joins them into one
string, everywhere, with no operator and no brackets. Inside a string, `$` is always just a character, so
`"Price: $5"` needs no escape and `\$` isn't needed. `println` is an ordinary function that takes a `String`.

```
println("Hello, " $name)                   // Hello, Tankun
println("Hi, " $user.name "!")             // Hi, Tankun!
let $greeting: String = "Hello, " $name
println("Hello," $name)                    // Hello,Tankun: no space is added
```

Not decided yet: whether a value that isn't a `String`, such as an `Int`, is turned into text automatically, and whether
an operator like `+` can appear inside a join. Replaces the sketch's `"Hello, $name"` and `\$name`.

Claude proposed interpolation of variables and fields only; the owner said: "Fuck, new `println`" with
`println("Hello, " $name)`, then "Everywhere too, but maybe it should need `[]` elsewhere", explaining that a bare
`$name` "looks like another variable being declared (a little bit)". Claude worked out `[ ]` outside call arguments;
the owner said "Nvm", and when asked which part, chose: "`[]`". (Owner, 2026-11-13)

**D21. Turning a value into text is explicit, with `as String`.** A join (D20) only joins `String`s. Anything else is
converted where it can be seen, and forgetting it is refused with the one fix shown (D10). `println` only prints the
joined text, with no shaping options; formatting, such as two decimal places, is a separate tool for later.

```
println("Age: " $age as String)        // ok
println("Age: " $age)                  // CompileTimeError, fix: `$age as String`
```

Not decided yet: what each type's text looks like (a `bool`, a `Float`, a struct), and how `as` binds inside a longer
join. Cyborg has no joins; it uses a format print with holes, as Cyborg's design session described on 2026-11-13. The
owner said "Ask Cyborg"; Claude proposed automatic conversion with shaping labels; the owner said "It's `println`, not
a format version" and asked "Explicit conversion?"; asked how to spell it, the owner chose: "`as`". (Owner, 2026-11-13)

**D22. `give` and `copy` are lowercase.** Replaces the spelling in D7 and D10's example. Every Jernal keyword is
lowercase (`let`, `var`, `baked`, `fn`, `end`, `if`, `as`), and capitalized words look like type names (`List`,
`String`). The capitals came from Cyborg's spelling.

```
let $b: List = give $a
let $c: List = copy $a
```

The owner asked: "shouldn't `Give` be lowercase?"; Claude agreed; the owner chose: "yea". (Owner, 2026-11-13)

**D23. A join holds only text, names and `as`.** Settles what D20 and D21 left open. A join contains strings,
variables, fields and `as`, nothing else. `as` applies only to the one value right before it. Operators such as `+` are
refused inside a join, with a `fix:` that names a step first, as D19 does for long lines.

```
println("Age: " $age as String)            // converts $age, then joins
println("Total: " $a + $b as String)       // refused: name the step first
let $total: Int = $a + $b
println("Total: " $total as String)        // ok
```

Claude proposed it; the owner chose: "yea". (Owner, 2026-11-13)

**D24. The shape of a function.** Parameters go in `[ ]` (D15). `-> Type` gives the result, and leaving it out means
the function returns nothing. A result is given with `return`, written out; the last line is never the result by
itself. The closing `end fn` repeats the function's name.

```
fn add[$a: Int, $b: Int] -> Int:
    return $a + $b
end fn add

fn main[]:
    println("Hello")
end fn main
```

The owner's sketch had `fn main[]:`, `end fn main` and "implicit return void"; Claude proposed the rest; the owner
chose: "yea". (Owner, 2026-11-13)

**D25. Sized types like `i32` are all available.** Jernal is progressive: the everyday types, such as `Int`, come first,
and sized types such as `i32` (a 32-bit signed integer) are there for whoever needs them. Which sized types exist and
what `Int`'s size is aren't settled; the sketch's comment says `Int` is `i64`. The sketch said "i32 style types are
usable, just not here"; the owner said: "`i32` style types are all available, it's progressive". (Owner, 2026-11-13)

**D26. `return early` leaves a function that returns nothing.** Reaching `end fn` ends such a function, so nothing is
written at the end. Leaving before the end is the only leave the page doesn't otherwise show, so it says so:
`return early`. A function with a result always uses `return $value`, wherever it is.

```
fn greet[$name: String]:
    if $name == "":
        return early
    end if
    println("Hi " $name)
end fn greet
```

The owner asked: "How do you leave early? `return early`?" Claude first suggested a bare `return`; the owner asked: "If
it's bare `return`, why don't you write at the end too? Even when not leaving early?" Claude agreed `return early` is
the consistent choice; the owner chose: "yea". (Owner, 2026-11-13)

**D27. The comparisons: `==`, `!=`, `<`, `>`, `at_least`, `at_most`.** Equality is `==` and `!=`. "Greater or equal"
and "less or equal" are the words `at_least` and `at_most`, replacing the `>=` and `<=` that D18 mentioned, since a
word is shorter to read in your head. `>=` and `<=` are refused, with the word as the fix. `<` and `>` stay, spaced as
in D18. `=` in a condition is refused, with `fix: ==`.

```
if $age == 18:
if $age != 18:
if $age < 18:
if $age at_least 18:
if $age at_most 65:
if $age = 18:            // refused, fix: `==`
if $age >= 18:           // refused, fix: `at_least`
```

Claude proposed `==` and `!=`; the owner chose: "`==`, `!=`, `at_least`, `at_most`, `>=` is longer when you read in
mind". (Owner, 2026-11-13)

**D28. `and`, `or`, `not`, and `.both` to skip nothing.** Conditions combine with the words `and`, `or` and `not`.
`and` and `or` short-circuit: the right side runs only if it can still change the answer. `and.both` and `or.both`
always run both sides. `&&`, `||` and `!` are refused, with the word as the fix; `!=` stays (D27).

```
if $age at_least 18 and $has_ticket:
if not $done:
if $user_ok and load_profile():               // load_profile() runs only if $user_ok is true
if check_a() and.both check_b():              // both always run
```

Claude proposed the words; the owner chose: "yea, they short-circuit, with `.both`, they don't". (Owner, 2026-11-13)

**D29. The shape of `if`.** Further branches are `else if` (two words, no `elif`) and `else:`. Every line that opens a
block ends with `:`, and one `end if` closes the whole chain.

```
if $age < 13:
    println("kid")
else if $age < 18:
    println("teen")
else:
    println("adult")
end if
```

Claude proposed it; the owner chose: "yea". (Owner, 2026-11-13)

**D30. Loops: `for`, `while`, `break`, and no `continue`.** `for ... in` goes through something, and `while` runs while
a condition holds; each is closed by its own `end`. `break` leaves the innermost loop at once, and the program carries
on after its `end`. There is no `continue` and no `skip`: an item is skipped by wrapping the work in an `if`, so the
skipped path shows as structure instead of a hidden jump. This matches Cyborg (its D128, from Radium), as Cyborg's
design session described on 2026-11-13.

```
for $item in $list:
    if $item == "end":
        break
    end if
    if $item != "":
        println($item)
    end if
end for

while $count < 10:
    ...
end while
```

Claude proposed `skip` and `stop`; the owner said "Ask Cyborg about `continue` `brea`k", then "Don't style guides
dislike `continue`? I mean, I don't like it either", asked "yea but what does `break` do?", and chose: "`break`, `stop`
just makes me think of the entire program". (Owner, 2026-11-13)

**D31. Named loops.** A loop may have a name, written after `for` or `while`, and its closer then repeats it.
`break name` leaves that loop and every loop inside it; a plain `break` still leaves the innermost one. As in Cyborg
(its D128).

```
for rows $row in $grid:
    for $cell in $row:
        if $cell == $target:
            break rows
        end if
    end for
end for rows
```

Claude proposed it from Cyborg's design session's advice; the owner chose: "yea". (Owner, 2026-11-13)
