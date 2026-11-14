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

**D32. No compound assignment.** There is no `+=`, `-=`, `*=` or the like, nor `++`. They break the reading flow: the
operation sits on the left and the amount comes after it, where `$count + 1` reads in order. How a variable gets its
new value is not decided yet (since decided in D33). The owner said: "no things that break reading flow, like `+=`. It places `thing + 1` in
front, instead of in back". (Owner, 2026-11-13)

**D33. `change` gives a `var` a new value.** Every update starts with `change`, for a whole variable, one field or one
item. A bare `$x = ...` is refused, with `fix: change $x = ...`. `change` on a `let` is refused, since it can't change.
So every line that touches a variable starts with a word (`let`, `var`, `change`), and the left edge of the code shows
what happens. As in Cyborg, as Cyborg's design session described on 2026-11-13.

```
var $count: Int = 0
change $count = $count + 1
change $user.name = "Tankun"
change $xs[pos: 3] = 10
$count = 5                       // refused, fix: `change $count = 5`
```

**D34. `decl` and `assign`: a variable whose value comes later.** `decl` declares a variable with its type and no
value. `assign` gives it its first value, exactly once on each path through the code. Reading it before every path has
assigned it is refused when compiling, so nothing can ever read it empty. After that it acts like a `let`. `assign` on
something that already has a value is refused, with `fix: change`. As in Cyborg (its D203). How to declare one that can
change later is not decided yet.

```
decl $label: String
if $hot:
    assign $label = "hot"
else:
    assign $label = "cold"
end if
println($label)
```

The owner said: "Cyborg has `change`, `let`, `assign`, and `decl`, ask." Claude proposed `change`, with `decl` and
`assign` to follow; the owner chose: "yea to both, actually". (Owner, 2026-11-13)

**D35. `decl var` for a later value that can change.** Settles what D34 left open. `decl` declares a `let`, and
`decl var` declares a `var`, which `change` can update after its first `assign`.

```
decl var $total: Int
if $hot:
    assign $total = 10
else:
    assign $total = 0
end if
change $total = $total + 1
```

**D36. `shadow` declares a name that already exists.** `shadow` gives an existing name a new value, which may have a
new type; from then on the name means the new one. `shadow` means `let`, and `shadow var` means `var`, matching `decl`.

- Declaring an existing name with `let`, `var` or `decl` is refused, with `fix: shadow`, so reusing a name is always on
  purpose.
- `shadow` on a name that doesn't exist is refused, with `fix: let`.
- It works in the same block or an inner one. In an inner block, the old name comes back after the block's `end`.
- It works after `give`: the given name is retired, and `shadow` makes a fresh one.

```
let $total: Int = 5
shadow $total: String = $total as String
```

| Can't change | Can change |
|---|---|
| `let $x: Int = 1` | `var $x: Int = 1` |
| `decl $x: Int` | `decl var $x: Int` |
| `shadow $x: Int = 1` | `shadow var $x: Int = 1` |

Cyborg has no `shadow`, and declaring a name twice is still open there, as Cyborg's design session said on
2026-11-13. The owner said "`shadow` is also real", then "That rule, no need to ask now? `decl` means `let`, `decl var`
means `var`?"; Claude proposed these rules; the owner chose: "yea". (Owner, 2026-11-13)

**D37. Ranges are labelled: `range[from:, to: or before:, step_by:]`.** `from:` is required, then either `to:`, which
includes the end, or `before:`, which stops before it, then an optional `step_by:`, in that order. There is no `..`.

```
for $i in range[from: 1, to: 5]:                  // 1, 2, 3, 4, 5
for $i in range[from: 0, before: 5]:              // 0, 1, 2, 3, 4
for $i in range[from: 0, to: 10, step_by: 2]:     // 0, 2, 4, 6, 8, 10
for $i in range[from: 5, to: 1, step_by: -1]:     // 5, 4, 3, 2, 1
for $p in range[from: 1, to: $xs.length]:         // every position, for $xs[pos: $p]
```

- A range whose numbers are known when compiling and that can never reach its end is refused, such as `from: 5, to: 1`
  with no negative step. One that's only known while running runs zero times.
- A `step_by:` of 0 is a `RuntimeError`, since the loop would never end.
- The loop's own variable can't be changed inside the loop.

This is Cyborg's range (its D128, from Radium, with D145), as Cyborg's design session described on 2026-11-13. Claude
first proposed the words `1 to 5` and `0 until 5`; the owner said "Ask Cyborg"; Claude then proposed Cyborg's labels;
the owner chose: "yup". (Owner, 2026-11-13)

**D38. `sum`, and it's always exact.** Jernal has a `sum` like Python's, but the plain one is the correct one: exact for
`Int` and `Decimal`, and for floats it rounds once at the end, like Python's `math.fsum`, instead of piling up a
rounding error on every step. An empty list sums to `0`. The result has the items' type. Whether it's spelled
`sum($xs)` or `$xs.sum()` depends on whether Jernal has methods, which isn't decided yet.

The owner asked: "Btw, I think we should have Python's `sum`?" Claude proposed making the plain `sum` the exact one;
the owner chose: "yea". (Owner, 2026-11-13)

**D39. `at pos` and `at offset` give a loop the item's place.** After the list in a `for`, `at pos $p` gives each item's
position counting from 1, and `at offset $o` counting from 0, with the same words as indexing (D17). It's optional:
without it, the loop is the plain one from D30.

```
for $name in $names at pos $p:
    println($p as String ". " $name)        // 1. Ann, 2. Bob, 3. Cat
end for

for $name in $names at offset $o:           // $o is 0, 1, 2
```

Cyborg's design session advised deciding this early; Cyborg has no such loop. The owner asked "What does that do?" and
"Is `at` a good spelling?"; Claude compared it with `with` and Python's order; the owner chose: "`at`". (Owner,
2026-11-13)

**D40. Methods.** Values have methods, called with a dot, so steps read left to right in the order they happen, as D32
wants. Plain functions stay for what doesn't belong to a value, such as `println(...)` and `now()`. This settles D38's
spelling: `$xs.sum()`.

```
let $clean: String = $text.trim().upper()     // not upper(trim($text))
let $total: Int = $prices.sum()
```

How methods are declared is not decided yet. Claude proposed methods, citing D32's reading flow; the owner chose:
"yea". (Owner, 2026-11-13)

**D41. Narrowings on `fn`.** What kind of function it is goes on `fn` after a dot, and the closer repeats all of it,
narrowings and name.

- `fn.pure`: the same input always gives the same output, and nothing else changes or is seen: no I/O, and only pure
  functions are called. The compiler refuses anything else inside it.
- `fn.pure.baked`: pure, and can also run while compiling, for a `let baked` (D5). It runs normally otherwise.
- Narrowings go strongest first, so it's `fn.pure.baked`, never `fn.baked.pure`; the wrong order is refused, with the
  right one as the fix.
- `fn main` stays plain.

```
fn.pure area[$w: Int, $h: Int] -> Int:
    return $w * $h
end fn.pure area

fn.pure.baked seconds_in[$days: Int] -> Int:
    return $days * 86400
end fn.pure.baked seconds_in

let baked $week: Int = seconds_in(7)
```

This is Cyborg's (its D86, D91, D121, D223), as Cyborg's design session described on 2026-11-13. The owner said
"CyborgPL has an interesting function making system, ask", then "Fuck, I meant Cyborg"; Claude proposed narrowings,
with the closer repeating them; the owner chose: "yes, and repeat". (Owner, 2026-11-13)

**D42. The top of a body: `labels`, `defaults`, `requires`, `ensures`.** Before any code, a function body may say how
to call it and what it promises, always in this order:

- `labels`: which parameters are written with a label at the call. Unlabelled arguments come first, in order.
- `defaults`: a labelled parameter's value when the call leaves it off.
- `requires` and `ensures`: contracts, checked at runtime (D8). How `ensures` names the result is not decided yet.

```
fn first_word[$text: String, $limit: Int] -> String:
    labels [$limit as limit]
    defaults [$limit = 40]
    requires $limit at_least 1
    ...
end fn first_word

first_word($text, limit: 20)
first_word($text)                  // $limit is 40
```

Any function can have labels and defaults, not only special ones, as CyborgPL's design session advised. This is
Cyborg's (its D52, D113, D114), as Cyborg's design session described on 2026-11-13. Claude proposed it; the owner chose:
"yea". (Owner, 2026-11-13)

**D43. `mut` replaces `var`, everywhere.** "Can change" is written `mut`, after the word that declares the name.
Replaces `var` in D5, D7, D33, D35 and D36.

| Can't change | Can change |
|---|---|
| `let $x: Int = 1` | `let mut $x: Int = 1` |
| `decl $x: Int` | `decl mut $x: Int` |
| `shadow $x: Int = 1` | `shadow mut $x: Int = 1` |

A method that changes the value it's called on says so once, in its declaration, with `mut $self`. Calls are written
plainly, and calling such a method on a value that can't change is refused. A plain `$self` can't be changed inside the
method.

```
fn warm_up[mut $self: Reading, $by: Int]:
    labels [$by as by]
    change $self.celsius = $self.celsius + $by
end fn warm_up

let mut $r: Reading = Reading.new(20)
$r.warm_up(by: 2)               // fine
let $s: Reading = Reading.new(5)
$s.warm_up(by: 2)               // refused: $s can't change
```

Claude proposed marking changing methods, first with `change` at the call, then `%%`; the owner said "Maybe a symbol
instead? `change` reads weird there" and "Do we really need this?" Claude proposed marking it once in the declaration,
with `var $self`; the owner chose: "Actually, let's change to `let mut`, and `mut` everywhere. It just reads better".
(Owner, 2026-11-13)

**D44. Function narrowings: one name, several named kinds.** After a function's name, `.` picks a kind of it:
`show.stored`, `show.hex`. There are two sorts:

- **A preset** only fills in some of the function's labelled arguments. It's declared in the header (D42), as a
  `presets` line after `defaults`, and has no body of its own. `show.stored()` is exactly `show(digits: all)`.
- **A narrowing with its own code** is a function with a dotted name, `fn show.hex`, for a kind that works too
  differently to be a setting. It needs `show` to exist.

```
fn show[$x: Float, $digits: Digits] -> String:
    labels [$digits as digits]
    defaults [$digits = shortest]
    presets [stored = [$digits = all]]
    ...
end fn show

fn show.hex[$x: Float] -> String:
    ...
end fn show.hex

$x.show()                 // shortest
$x.show.stored()          // show(digits: all)
$x.show.hex()             // its own function
```

- Presets stack, one per `.`. A chain that sets one parameter twice is refused.
- There's no collection block: everything about `show` is in its header or in a `fn show.something`.
- A dotted name in a declaration always means a narrowing, so methods are not declared as `fn Type.name`.

This combines CyborgPL's (dotted functions, presets), Radium's (its D57, `narrowings.fn`, and its advice to give
presets a visible word) and Cyborg's call-side `fmt_print.stored`, as their design sessions described on 2026-11-13.
"Variants" are something else: one name with several parameter lists, CyborgPL's `versions`, which is not decided yet.
The owner said "Ask Radium and CyborgPL, then", "Function narrowings, they call it. And also variants too, I think
they're diff", confirmed variants are versions ("yea"), asked "What's the idea?", and chose: "Ah yea". (Owner,
2026-11-13)

**D45. `fam.fn`: everything under one name.** Replaces how D44 declares narrowings: there is no `presets` header
line and no `fn show.hex` outside a family. What a narrowing is stays as in D44. Plain `fn` stays for single functions
(D24); a `fam.fn` block is for three things:

1. a function and its narrowings and presets,
2. a group of related functions,
3. a type's makers and methods.

Inside `fam.fn X`, names are written short, and each one's full name is `X.name`. A function named `X` itself is the
family's own function, called as `X(...)`. A narrowing on `fam.fn`, such as `fam.fn.pure`, applies to every function
inside. The closer repeats everything, as in D41.

```
fam.fn show:
    fn show[$x: Float, $digits: Digits] -> String:    // show(...)
        labels [$digits as digits]
        defaults [$digits = shortest]
        ...
    end fn show

    preset stored [$digits = all]                      // show.stored(...): fills in arguments, no body

    fn hex[$x: Float] -> String:                       // show.hex(...): its own code
        ...
    end fn hex
end fam.fn show

fam.fn.pure geometry:
    fn area[$w: Int, $h: Int] -> Int:                  // geometry.area(3, 4)
        return $w * $h
    end fn area
end fam.fn.pure geometry

fam.fn Reading:
    fn new[$celsius: Int] -> Reading:                  // Reading.new(20)
        ...
    end fn new

    fn warm_up[mut $self: Reading, $by: Int]:          // $r.warm_up(by: 2)
        ...
    end fn warm_up
end fam.fn Reading
```

- A preset is written with the word `preset` and has no body, so it can't be mistaken for a function.
- In a family named after a type, a function whose first parameter is `$self` of that type is a method.
- Turning a plain function into a family later changes no calls.

Not decided yet: versions (D44's "variants"), whether a type can have more than one family, and a member pointing at a
function elsewhere. `fam.fn` descends from CyborgPL's `coll.fn` through Radium's `narrowings.fn` to Cyborg's `fam.fn`;
the owner said: "`fam` comes from Radium's `narrowings` that then comes from CyborgPL's `coll`". The owner asked
"What's more powerful?"; Claude said the block, and proposed `fam.fn` for all three uses; the owner asked "So, we would
have no single functions?" and "Let me see fam.fn syntax", and chose: "yea". (Owner, 2026-11-13)

**D46. Versions: one name, several parameter lists.** Settles D45's "versions". A `versions` block inside a family
writes the name once, then each version as its parameter list and body. The compiler picks a version by the number of
arguments and their exact types.

```
fam.fn area:
    versions area:
        [$side: Int] -> Int:
            return $side * $side
        end version
        [$w: Int, $h: Int] -> Int:
            return $w * $h
        end version
    end versions area
end fam.fn area

area(3)         // 9
area(3, 4)      // 12
```

- Versions exist only inside a family. The same `fn` written twice anywhere else is refused.
- Two versions that could take the same call are refused where they're written, and so is a default that would make
  them overlap, so adding a default never changes which version a call reaches.

This is CyborgPL's `versions` (2026-10-21), as CyborgPL's design session described on 2026-11-13; the owner had asked
there: "Wait, why are there two `say`s? Isn't supposed to be one, and narrowings?". Claude proposed it for Jernal; the
owner chose: "yea". (Owner, 2026-11-13)

**D47. One family per type, in the same place as the type.** A type's makers and methods are exactly what's in its one
`fam.fn` block. A second `fam.fn` with the same name is refused. To add helpers to a type you didn't write, such as a
library's type or `String`, write your own family of plain functions:

```
fam.fn text_tools:
    fn shout[$s: String] -> String:
        ...
    end fn shout
end fam.fn text_tools

text_tools.shout($name)       // not $name.shout()
```

Settles one of D45's open questions. Cyborg's design session flagged it as still open in Cyborg. Claude proposed one
block per type; the owner asked "Wdym by that?" and "Can't you just write at the same place?", and chose: "yea".
(Owner, 2026-11-13)

**D48. Failures: Cyborg's core.** A function lists the failures it can raise in its header, after the result type, and
raises one with `fail`, which leaves the function. Failures are their own track, not a `Result` value, and can carry
data. A named set of failures is a family, `fam.failure`.

```
fn half[$n: Int] -> Int fails [odd, negative[got: Int]]:
    ...
    fail negative[got = $n]
end fn half

fam.failure file_failed:
    not_found
    denied
    disk_full[free: Int]
end fam.failure file_failed
```

A caller has four tools:

```
let $f: File = open($path)?                      // pass it up; refused unless this function lists it
let $port: Int = read_port() ?? 8080             // use this value instead
let $w: String = first_word($text) otherwise:    // every failure still possible must be covered
    case too_long:
        instead "…"
    case no_words $f:                            // $f names the failure, to read its data
        instead "(none)"
end otherwise
let $w: String = first_word($text) otherwise word_failed.use_placeholder
```

- `instead` gives the value used in place of the failed call. An arm may also `return`, `break` or `fail`.
- `fam.handler` holds named, reusable sets of arms, used after `otherwise` as if written at the call. A handler that
  can `return` or `break` is marked `*` where it's used (`otherwise word_failed.*bail`), so a jump out is always
  visible; leaving it off, or putting it on one that can't jump, is refused.
- A failure nobody handles crashes loudly. Handling is opt-in; a linter can make it stricter.
- Failures are real events a program can handle, such as a missing file. Failed checks (D8, D9) are bugs in the code's
  own assumptions, such as overflow or a false `requires`; they can't be handled and are `RuntimeError`s.

Not decided yet: the list of which problems are failures and which are checks (Cyborg's design session advises writing
it first), and how a failure is ignored on purpose (Cyborg writes `?? void`). This is Cyborg's (its D44, D45, D47, D96,
D139, D209), as Cyborg's design session described on 2026-11-13; in Cyborg the owner said "`?` = `try`, `??` =
`otherwise`", "you could use handler collections" and "we default to crash, and then opt-in handle". The owner said
"Let's do err handling now. Ask Cyborg"; Claude proposed taking the core as it is; the owner chose: "yea". (Owner,
2026-11-13)

**D49. Every family writes its members short, with a keyword.** One rule for every kind of family, extending D45:
inside `fam.X name`, each member is written by its short name after a keyword saying what it is, and its full name is
`name.member`. `fam.fn` uses `fn`, `fam.handler` uses `handler`, and `fam.failure` uses `failure`. Replaces the
keyword-less `not_found` in D48's example.

```
fam.failure file_failed:
    failure not_found
    failure denied
    failure disk_full[free: Int]
end fam.failure file_failed

fam.handler word_failed:
    handler use_placeholder:
        case too_long:
            instead "…"
        case no_words:
            instead "(none)"
    end handler use_placeholder

    handler bail:
        case too_long:
            return early
        case no_words:
            return early
    end handler bail
end fam.handler word_failed

let $w: String = first_word($text) otherwise word_failed.use_placeholder
let $w: String = first_word($text) otherwise word_failed.*bail
```

- `*` goes on the use, never on the declaration; the compiler works out whether a handler can jump.
- A handler's arms are checked at each use, against the failures still possible there, so one handler may cover
  several failure families.
- Not decided yet: handlers taking arguments, and `pub` on families and their members.

Cyborg writes members by their full dotted name with no keyword (from Radium's spelling, with no decision of its own),
except in its `fam.fn`, as Cyborg's design session described on 2026-11-13. The owner asked "Where's handler fam?" and
"Ask"; Claude offered short names with a keyword everywhere, or full names everywhere; the owner chose: "A". (Owner,
2026-11-13)

**D50. Garbage collection only.** Memory is managed by a garbage collector alone, with no reference counting. Passing
references around costs nothing, and cycles need no special handling. `give` already proves when a value has a single
owner, so reference counts would add nothing for that. `copy` copies right away, where it's written; a compiler may
make it lazy (copy-on-write) only where it can prove nobody could notice. Things like open files aren't freed the moment
they're unused, so they need explicit cleanup, which is not decided yet. The owner's sketch already said "GC"; the owner
asked "What if we change to copy-on-write?", "What if we go both RC and GC? And copy-on-write" and "What if we go GC
only?"; Claude proposed GC only, with `copy` copying right away; the owner chose: "yea". (Owner, 2026-11-14)

**D51. `must_give` types must be handed off exactly once.** A type marked `must_give` has to be given away with `give`
exactly once on every path, or the program doesn't compile. It's for things that have to be closed or released, such
as files, connections and locks: the garbage collector handles memory, and `must_give` makes sure nobody forgets to
close. Every way out of a function counts, including `return early`, `?` and a failure. It's checked when compiling,
with nothing at runtime. Replaces D7's "no `must_Give`". How a type is marked depends on how types are declared, which
is not decided yet.

```
let $f: File = open($path)?
println($f.read_line())
close(give $f)                 // leaving this out is a CompileTimeError
```

From Cyborg's `must_Give` (its D2). The owner said: "Cyborg has a `must_Give` struct"; Claude proposed it for files and
connections, after D50 left them without cleanup; the owner chose: "Yes". (Owner, 2026-11-14)

**D52. `copy` is deep.** `copy` duplicates everything that can change, all the way down, so changing the copy never
changes the original, however deeply nested. Frozen parts, such as `let` values, numbers and strings, are shared instead
of duplicated, since nobody can tell the difference; so `copy` of a `let` value costs nothing. A value with a
`must_give` part inside (D51) can't be copied, and is refused with `give` as the fix.

```
let mut $grid: List<List<Int>> = [[1, 2], [3, 4]]
let mut $other: List<List<Int>> = copy $grid
change $other[pos: 1][pos: 1] = 9      // $grid is still [[1, 2], [3, 4]]
```

The owner asked: "How deep does `copy` copy?"; Claude proposed deep, sharing frozen parts; the owner chose: "yea".
(Owner, 2026-11-14)

**D53. Which problems are failures and which are checks.** Failures are real-world events a program can handle (D48).
Checks are bugs in the program's own assumptions: they are `RuntimeError`s, can't be handled, and are prevented up
front instead, with an `if` first or by D8's compile-time checks.

Failures:

| Problem | Example |
|---|---|
| a file not found, no permission, a full disk | `open($path)` |
| the network down, a connection lost | `connect($host)` |
| text that isn't a number | turning `"abc"` into an `Int` |
| text too long for a limit | a bounded string |

Checks:

| Problem | Example |
|---|---|
| a position outside the list | `$xs[pos: 0]`, `$xs[pos: 99]` |
| dividing by zero | `$a / 0` |
| a false contract | `requires $n at_least 1` |
| a `step_by:` of 0 | a range that never ends |
| a number too big for its type | an `Int` overflowing (D54) |
| running out of memory | |

A position that comes from outside, such as user input, can be asked for as a failure instead: a method like
`$xs.get(pos: $p)` fails where `$xs[pos: $p]` is a check. Its exact name is not decided yet. Cyborg's design session
advised writing this list first. Claude proposed it; the owner chose: "yea". (Owner, 2026-11-14)

**D54. `Int` is `i64`.** Settles D25's open question: `Int` is a 64-bit signed integer. It never wraps: going past its
range is a check (D53). The owner said: "(`Int` is `i64`)". (Owner, 2026-11-14)

**D55. `?? ignore` drops a failure on purpose.** Settles D48's open question. After a call whose failure doesn't
matter, `?? ignore` drops it, so searching for `ignore` finds every failure dropped on purpose. A call with a result uses
`??` with a value instead (D48).

```
save_backup($data) ?? ignore
```

Cyborg writes `?? void`, but Jernal has no `void` word (D26). Claude proposed `?? ignore`; the owner chose: "yea".
(Owner, 2026-11-14)

**D56. Structs.** A struct is declared as a block, with fields written without `$`, one per line, and the closer
repeats the name. It's built with `[ ]` and `=`, since `[ ]` describes (D15), and its fields are read with `.`.
Changing a field needs the whole variable to be `mut` (D43); single fields aren't marked as changeable. Properties are
narrowings on `struct`, strongest first, and the closer repeats them, as on `fn` (D41); this is how D51's `must_give` is
marked. Type names are capitalized (`Reading`, `OpenFile`, `Int`, `String`), and sized types stay lowercase (`i32`,
D25).

```
struct Reading:
    celsius: Int
    place: String
end struct Reading

let mut $r: Reading = Reading[celsius = 22, place = "Bangkok"]
println($r.place)
change $r.celsius = 23

struct.must_give File:
    ...
end struct.must_give File
```

Not decided yet: field defaults, building with fields out of order, and `pub` on fields. This matches Cyborg's struct
(its D57, from Radium), as Cyborg's design session described on 2026-11-14, except that Cyborg's type names are
lowercase. The owner said "Ask Cyborg"; Claude proposed this form with capitalized names; the owner chose: "yea".
(Owner, 2026-11-14)

**D57. Field defaults, and any order when building.** A field may have a default, written `= value` after its type; it
can then be left out when building, while a field without one must always be given. Fields can be given in any order
when building, since each is named.

```
struct Reading:
    celsius: Int
    place: String = "home"
end struct Reading

let $a: Reading = Reading[celsius = 22]                       // place is "home"
let $b: Reading = Reading[place = "Bangkok", celsius = 22]
let $c: Reading = Reading[place = "Bangkok"]                  // refused: celsius has no default
```

Settles two of D56's open questions; both are still open in Cyborg. Claude proposed them; the owner chose: "yea".
(Owner, 2026-11-14)

**D58. Units: Cyborg's system, after v1.** Jernal takes Cyborg's unit system (its standard 2.16), as Cyborg's design
session described on 2026-11-14, adapted to Jernal's style. It's designed now and built after v1.

```
fam.unit money:
    unit cents: base
    unit dollars = 100 cents
end fam.unit money

fam.unit motion:
    unit speed = length.meters per time.seconds
    unit area = length.meters x length.meters
end fam.unit motion

let $price: Int[unit: money.cents] = 1999 money.cents
let $m: Float[unit: length.meters] = $km as Float[unit: length.meters]
```

- Units are opt-in: a plain `Int` is just a number, and a unit applies only where a type asks for one with `unit:`.
  Values then write theirs after the number, naming its family.
- Mixing units, or leaving one off where it's needed, is refused.
- Converting within a family uses `as`. An integer going to a bigger unit says how it rounds: `as.trunc`, `as.floor`,
  or `as.exact`, which fails if anything would be lost.
- Combined units are declared once with `per` and `x`. The compiler tracks every value as powers of its base units,
  and storing needs a declared unit whose powers match.
- Scales with an offset, such as temperature, separate points from spans: a point plus a span is a point, a point minus
  a point is a span, and a point plus a point is refused.
- Prefixes are declared once and opted into, so `kilo` on `length.meters` gives `length.kilometers`.
- `std` ships `time`, `storage` and `angle`; `sin` asks for radians.

Differences from Cyborg: there's no built-in `items` unit, since D17 indexes with plain `pos:` and `offset:`, so
lengths stay plain `Int`. Cyborg's placeholder words (`offset`, `with`, `fam.prefix`, `decibels of`) are placeholders
here too. The owner said: "Cyborg's unit system could very much be copied here, instead of redesigning"; Claude adapted
it; the owner chose: "yea, post-v1". (Owner, 2026-11-14)

**D59. Imports come from the manifest, and every clash is an error.** A file has no import lines. Every package the
manifest lists is visible by short names, with no path, and a full path (`http::get`, `pkg::get`) is needed only when a
short name clashes. A clash is always a `CompileTimeError`, never a quiet pick, even when one side is the program's own
code; the error lists the full paths. So a library that later adds a name already in use causes an error, not a silent
change of meaning. `use` stays optional, for giving something a short name of the writer's choosing.

```
// the manifest lists std and http
fn main[]:
    println("hi")                       // from std
    let $page: String = get($url)?      // from http: nothing else is called `get`
end fn main
```

The owner's sketch said "use full path syntax only on clash" and "config, imports, and stuff are handled by manifest".
Cyborg has `import` lines instead, and its design session advised keeping clashes an error, as it described on
2026-11-14. Claude proposed this; the owner chose: "yea". (Owner, 2026-11-14)

**D60. `use` gives a checked or quoted short name.** `use path as name` gives something a short name in that file. The
path is written short, like any name (D59). One name per `use`, with no wildcards.

- An unquoted name must match the last word of its path, so it can't lie about what it is.
- A quoted name is the writer's free choice. The quotes appear only on the `use` line. A quoted name nothing could
  call, such as `""` or `"fn"`, is refused.
- If the part before the last dot is a function, the unquoted short name can't be the narrowing alone, since `stored`
  on its own reads like a different action. A quoted name is allowed.

```
use time.seconds as seconds          // a family member
use time.seconds as "secs"           // quoted: any name
use time.seconds as minutes          // refused: it would lie
use geometry.area as area            // a family member
use show.stored as stored            // refused: `show` is a function
use show.stored as "show_stored"     // quoted: allowed
```

This is Cyborg's `use` (its D93, D150, D151, D220), as Cyborg's design session described on 2026-11-14. The owner
asked about `use time.seconds as seconds` and `as "secs"`, then pointed out: "`time.seconds` is a narrowing,
`show.stored` is too." Claude narrowed the rule to narrowings of a function, with quoted names allowed; the owner
chose: "yea". (Owner, 2026-11-14)

**D61. `type.alias` and `type.new`.** A type can be given another name in two ways, and there's no bare `type`:

- `type.alias` is the same type under another name, fully interchangeable.
- `type.new` is a distinct type over the same data, which doesn't mix with others. Crossing in either direction uses
  `as`, which can't fail. A literal takes the type of where it lands.

```
type.alias Numbers = List<Int>
type.new UserId = Int
type.new OrderId = Int

let $u: UserId = 5
let $o: OrderId = 7
if $u == $o:                            // refused: UserId and OrderId don't mix
let $n: Int = $u as Int

fam.type.new Ids:
    type User = Int
    type Order = Int
end fam.type.new Ids                    // Ids.User, Ids.Order
```

`type.new` is for things units (D58) don't fit, such as ids. This is Cyborg's (its D134, D141), as Cyborg's design
session described on 2026-11-14. Claude proposed it in Jernal's style; the owner chose: "yea". (Owner, 2026-11-14)

**D62. `fn.main` is where a program starts.** The entry point is a narrowing, `fn.main`, not a function with a special
name. Replaces D41's "`fn main` stays plain". It takes no parameters (command-line arguments will come from a package
later) and returns nothing, ending at `end fn.main` or with `return early`; its exit code follows D11. A program has
exactly one: none is refused, and so are two. A plain `fn main` is refused, with `fix: fn.main`.

```
fn.main[]:
    println("Hello, World!")
end fn.main
```

This is Cyborg's `fn.main` (its D11, D214), as Cyborg's design session described on 2026-11-14. The owner asked "As
for `fn main`, should it be `fn.main`?", and said "Actually, you can make your own `fn main`, `fn my::main`. Ask Cyborg
for more details"; Claude proposed this; the owner chose: "yea". How a name that clashes with the language is written
is not decided yet. (Owner, 2026-11-14)

**D63. `my::` only for names that clash with the language.** A name of the program's own that is also a built-in word
(a keyword, a word operator such as `and` or `at_least`, a built-in type such as `Int`, or `main`) is written with
`my::` wherever it appears: its declaration, its closer and every use. Every other name stays bare. If Jernal later adds
a built-in word that old code used as a bare name, that code gets a `CompileTimeError` saying to add `my::`, never a
silent change of meaning. `my::` is for clashes with the language; `pkg::` (D59) is for clashes with a package.

```
fn greet[]:                     // no clash: bare
...
fn my::main[]:                  // clashes with `main`
...
end fn my::main
my::main()
my::and($x, $y)                 // never mistaken for the operator `and`
```

This is Cyborg's `my::` (its D75, D214), as Cyborg's design session described on 2026-11-14. The owner asked "But is
`my::` required? Personally, I don't think it should be", then "Why not just require only for clashing ones? Current
clashing"; the owner chose: "yea". (Owner, 2026-11-14)

**D64. Collection literals, and map kinds.** Lists and maps are written with `[ ]`, and the declared type decides what
a literal is:

```
let $xs: List<Int> = [1, 2, 3]
let $ages: Map<String, Int> = ["Ann" => 30, "Bob" => 25]
let $none: List<Int> = []
let $nobody: Map<String, Int> = []
let $big: List<String> = [
    "first",
    "second",
]
```

- A map writes `key => value`. `->` already means "returns" (D24), and `=` builds structs (D56).
- `[]` is empty for both, as the type says (D14).
- A comma after the last item is allowed. Settles D19's open question.
- There are no tuples, since a struct names its fields, and no set literal.
- Maps come in kinds, as narrowings: `Map.hash` (no order), `Map.sorted` (by key) and `Map.insertion` (the order
  added). A bare `Map` is `Map.insertion`.
- Spelling out a default is allowed, never refused: `Map.insertion` like `Map`, `i64` like `Int`. Jernal is
  progressive, so the plain name comes first and the precise one is always there. The same goes for `String.utf8`.
- Narrowings are lowercase, even on a capitalized type: `String.utf8`, `Map.hash`.

Cyborg has only list and array literals, no map literal, and refuses a bare `map`, as Cyborg's design session
described on 2026-11-14; it suggested a separator other than `=` for maps. The owner said "Ask Cyborg"; Claude
proposed `->`; the owner said "That's already used for returns, though. Maybe `=>` instead?", asked "Is there only one
kind of `Map`? Isn't there more? Maybe with a dot?", chose "yea" to a bare `Map` meaning insertion order, and said:
"Should we refuse the same option? Like `Map.insertion` is refused, write `Map`? I don't think so, since `i64` would also
be refused. And we're not the same as Cyborg's pitch, we're progressive. So, `String.utf8` wouldn't be refused too. And
does the `Utf8` need to be big first letter?" (Owner, 2026-11-14)

**D65. The compiler: Rust, LLVM through `inkwell` and `llvm-sys`, and C++ where Rust can't reach.** The compiler is
written in Rust. It drives LLVM through `inkwell`, and through `llvm-sys` where `inkwell` doesn't cover something. What
neither can reach, such as parts of LLVM's C++ API, goes in small C++ pieces. This differs from Cyborg, which goes
through Lyftar and allows no C++. Claude proposed Rust with LLVM IR as text; the owner said "That's not fun, lol", and
chose: "Rust + Inkwell + llvm-sys + LLVM + C++ for Rust can't do?". (Owner, 2026-11-14)

**D66. The GC finds pointers with stack maps, from the start.** The compiler uses LLVM's `gc.statepoint` and
`gc.relocate`: at every safepoint (calls and allocations), a table says exactly where live pointers are, emitted into
`.llvm_stackmaps` by `RewriteStatepointsForGC`. Nothing is guessed and nothing is tracked while running, and objects can
move, since `gc.relocate` updates every pointer, which leaves room for a compacting or generational collector. What
`inkwell` can't reach goes in D65's C++ pieces. Long loops will need safepoint polls once there are threads. Claude
compared a shadow stack, stack maps and mostly-precise scanning; the owner asked "I heard there's an option that uses
both." and "Stack maps?", and chose: "stack maps from the start". (Owner, 2026-11-14)

**D67. A generational GC.** New objects are allocated by bumping a pointer in a small copying nursery, which is
collected often; objects that survive move to an old area collected by mark-and-sweep. Moving relies on D66's
`gc.relocate`. Write barriers catch an old object getting a pointer to a new one; frozen `let` values (D6) never change,
so they never trigger one. Claude compared non-moving, copying and generational collectors; the owner chose: "Gener".
(Owner, 2026-11-14)

**D68. A fully concurrent GC, from the start.** Both generations (D67) are collected alongside the running program,
so there are no long pauses, only brief ones to start and finish a collection. Moving objects while the program uses
them needs read barriers, a check on every pointer load, as well as D67's write barriers. That costs some throughput and
is the hardest GC design to get right; the model is Java's Generational ZGC. Claude compared stop-the-world, concurrent
and mixed, and recommended mixed; the owner asked "What has better perf?", said "I mean, my ass is not used to a long-ass
paused, tbh", asked "Concurent from statr?", and chose: "Fully concur, it seems fun." (Owner, 2026-11-14)

**D69. An oracle that ignores speed and keeps every check, and is also `Interp` mode.** Jernal has two
implementations. The oracle is a plain interpreter written straight from the spec: it never optimizes, and it never
drops a check, even one the compiler proves always passes (D9), so it's the safest way to run a program and the slowest.
The compiler must give byte-for-byte the same output as the oracle on every test and generated program; where they
differ, the spec decides which is wrong. The two stay apart: neither is written from the other's source, so their bugs
can't agree. The oracle is also the `Interp` build mode, which runs a program with no compiling. Other build modes are
not decided yet. This follows Cyborg's oracle (its rule 3) and multifinity's notes. Claude proposed it; the owner chose:
"Oracle that says fuck you to perf, and kisses safety's ass, and also somehow is in `Interp` mode." (Owner, 2026-11-14)

**D70. Build modes.** Jernal has six build modes, from multifinity's notes:

| Mode | What it's for | In v1 |
|---|---|---|
| `Interp` | runs on the oracle, with no compiling (D69) | yes |
| `Working` | everyday development: the optimization level is chosen, every check stays | yes |
| `FinalSafe` | release: fully optimized, keeps every check it can't prove away (D9) | yes |
| `FinalPerf` | release: fully optimized, drops some checks for speed | yes |
| `FinalQuick` | fast compiling, like Go; needs a second backend such as Cranelift | later |
| `UB++` | drops contracts and bounds checks, and anything wrong is undefined behaviour | later |

Not decided yet: exactly which checks `FinalPerf` drops. Claude proposed `Interp`, `Working` and `FinalSafe` for v1;
the owner chose: "Accept all of those. `Interp`, `Working`, `FinalSafe`, and `FinalPerf` is in v1." (Owner,
2026-11-14)

**D71. What `FinalPerf` does.** Settles D70's open question. `FinalPerf` is fully optimized and keeps no runtime checks;
it assumes the program has been tested. D9's "never a wrong answer" doesn't hold in it.

| What goes wrong | `FinalSafe` | `FinalPerf` |
|---|---|---|
| overflow on `+`, `-` or `*` | crash | wraps |
| a position out of bounds, dividing by zero, `step_by: 0` | crash | undefined behaviour |
| a false contract | crash | undefined behaviour; the optimizer may treat it as true |
| a failure nobody handled | crash | crash |
| a compile-time rule broken | refused | refused |

Overflow wraps rather than being undefined, since a plain `+` isn't a promise the writer made; `-` and `*` are decided
together with it. This is Cyborg's `FinalPerf` (its D41, D42), as Cyborg's design session described on 2026-11-14,
where the owner said "`FinalPerf` isn't comedic, it assumes you have tested it throughly already"; Cyborg had left `-`
and `x` undecided. The owner said "Funny, bro. It says fucking performance", asked "Did Cyborg dclaude says how
FinalPerf works?" and "ask"; Claude proposed Cyborg's, with all three operators wrapping; the owner chose: "yea".
(Owner, 2026-11-14)

**D72. No default build mode.** Every build and run names its mode; nothing is picked implicitly. As in Cyborg (its
D26). Claude proposed `Interp` for running and `Working` for building as defaults; the owner chose: "No". (Owner,
2026-11-14)

**D73. The oracle is written in OCaml, uses no shared GC, and the GC gets a torture mode.** The oracle (D69) is written
in OCaml, a different language from the compiler (D65), so nothing can be shared between them by accident. Jernal's
integers are `Int64` in the oracle, never OCaml's plain 63-bit `int`. The oracle doesn't share the compiler's garbage
collector: it relies on OCaml's own, since collection can't be seen in a Jernal program. Comparing compiled programs
against the oracle tests the real GC, since a GC bug changes the compiled output, and a GC torture option in `Working`
mode, which collects on every allocation, makes sure collections and timing windows happen even in small tests. The
owner said "SPARK?", then "No, no, no. I was joking"; asked "would they reuse the GC together? Comp and Orac" and "how
does testing against the oracle doesn't test the GC?", said "Yes, but should oracle use Rust or OCaml?", and chose:
"OCaml". (Owner, 2026-11-14)

**D74. Names: JernComp, JernGC, `.jern`, and the `jern` command.** The compiler is JernComp, and the garbage collector is
JernGC. Jernal files end in `.jern`, replacing the `.jernal` placeholder in earlier examples. The command is `jern`:

```
jern comp --FinalSafe       // compiles
jern run --FinalSafe        // compiles, then runs
jern run --Interp           // runs on the oracle
```

Every command names its mode (D72). Not decided yet: the oracle's name, the manifest's name and format, and how a file
or package is named on the command line. The owner chose these names. (Owner, 2026-11-14)

**D75. The oracle is JernOrac, and the manifest uses siml.** The oracle (D69, D73) is named JernOrac. The manifest is
written in siml, the format of Cyborg's `CyJet.siml`. The manifest's file name and contents are not decided yet. Claude
proposed JernOrac and asked between a standard format and a custom one like Cyborg's; the owner chose: "Yes, as for
the manifest though, `siml` is a lot more straight-forward". (Owner, 2026-11-14)

**D76. The package manager is Journey, and the manifest is `Journey.siml`.** Settles D75's open question. Every
program has a manifest, even Hello World. It holds, one fact per line in siml:

- `name` and `ver`: every project is a package. A version is a labelled date, biggest first, plus whether it breaks
  anything, such as `ver 2026y-11m-14d breaks`; the word for "doesn't break" is a placeholder, `same`.
- `need <package> <date>`, one per package, with the version always written. This is where D59's names come from.
- `rule` lines for the compiler's and linter's rules, so configuration stays out of the code.

```
// Journey.siml
name hello
ver 2026y-11m-14d same

need std 2026y-11m-14d
need http 2026y-11m-14d

rule mut.never_changed refuse
```

This is Cyborg's manifest (its D183, D189, D228 to D231, D265), as Cyborg's design session described on 2026-11-14,
without its `dialect` line, since Jernal has one compiler. siml is the owner's own format: one line per fact, values
separated by spaces, no sections, `=` or `;`, blank lines to group, quotes only when needed, `//` comments, and lists as
repeated lines. Nesting isn't designed yet. The owner said: "Could be `Journey` for package man."; Claude said it would
record `Journey.siml` with Cyborg's contents unless told otherwise. (Owner, 2026-11-14)

**D77. Modding: books, quills and Dialects.** A package (managed by Journey, D76) can have a **book**, its library
half, a **quill**, its compiler half, or both, under one name and version. These are Cyborg's kit and limb.

- **A quill** is a compiler extension: a native library (`.dylib`, `.so`, `.dll`) that JernComp loads while compiling.
  It's trusted when the manifest lists it, with no sandbox. None is privileged: Jernal's own extensions plug in the same
  way.
- **A quill's syntax is always marked**, in a fixed set of places (a type, a call, a prefix, a statement, a block, a
  raw block in another language, a manifest rule), so a quill never takes a plain word and two quills never clash. The
  marker is not decided yet; Cyborg uses `@`.
- **What a quill can do:** read the whole checked program; add errors and warnings, which only make programs stricter;
  define what its own marked items mean; produce Jernal code, which is checked like hand-written code, or LLVM IR,
  which is unchecked and listed in the build report; and prove checks can't fail, so they're dropped (except in
  `Working`).
- **What a quill can never do:** change what unmarked code means.
- **A Dialect** is a compiler forked from JernComp, for changing what plain code means. It doesn't have to follow any
  rules. Every manifest says which one it uses, and plain Jernal can't use a package written in a Dialect.

Not decided yet, as Cyborg's design session advised deciding early: the quills' actual interface and how it's
versioned, what "verified" means, and whether quills must keep builds reproducible. This is Cyborg's (its D186, D309 to
D311, D334 to D338), as Cyborg's design session described on 2026-11-14. The owner said "Let's decide modding" and "Ask
Cyborg", chose "yea" to both levels, asked "What should a kit and limb be called in Jernal?", and chose "Tes" to book
and quill. (Owner, 2026-11-14)

**D78. Quills use no marker, only Jernal's own shapes.** Settles D77's marker: there is none. A quill's names are
ordinary names, and a clash is an error (D59, D63). Quill syntax must use shapes Jernal already has:

- names: calls, types and narrowings;
- blocks in the `word ...:` / `end word` shape, so any tool can find where a block ends without knowing the quill;
- raw code in another language, always inside an `inline.something:` block, which tools leave alone.

There is no prefix-before-a-call form and no form in place of `=`; those become ordinary calls.

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

The manifest lists which quills a project uses; a file doesn't show which lines come from one. Cyborg marks every quill
item with `@`. The owner asked "Wait, how would you write in `.jern`" and "Do we really need `@`?", said "It doesn't
always mean dangerous, though. And I mean, you can just look at the manifest", and chose: "yea". (Owner, 2026-11-14)

**D79. What needs a shield, and Jernal isn't freestanding.** A shield is where code the compiler can't check lives.
These need one:

| Kind | Example |
|---|---|
| calling foreign code | a C library's function, a raw system call |
| raw pointers | making one, reading or writing through one, pointer arithmetic |
| inline foreign code | `inline.llvm_ir:`, inline assembly |
| reinterpreting memory | treating bytes as another type, C's untagged unions |
| memory outside the GC | manual `malloc`/`free`-style memory |
| handing a GC object to the outside | passing a list's buffer to C, which needs it pinned (D67, D68) |
| a quill's unchecked LLVM IR (D77) | counts as shield code automatically |

These don't: `FinalPerf` dropping checks (a build mode, D71), a quill producing Jernal code (checked, D77), files,
network, the clock and the environment (safe calls with failures, D48), and `give`, `copy`, `must_give` and `mut`
(checked when compiling). Threads changing shared data without coordination may need a shield once threads are
designed. How a shield is written is not decided yet.

Jernal isn't freestanding: every program runs with its runtime, including JernGC, on an operating system. The owner
asked "would we like shields?" and "First, define what kinds need shield", chose "Yes" to this list, and said: "Jernal
can't freestand, right? That's fine". (Owner, 2026-11-14)

**D80. How a shield is written.** A shield is a named block. Its body starts with `reason`, saying why the escape hatch
is needed, then `pin` for each GC object handed to the outside, then the code.

```
shield read_header:
    reason "libpng's C API takes a raw buffer"
    pin $buffer
    let $ptr: Ptr<u8> = $buffer.raw_address()
    let $status: i32 = png_read(give $ptr, $buffer.length)
end shield read_header
```

- A pinned object isn't moved or freed by the GC until the shield's `end`. Handing out an object that isn't pinned is
  refused.
- The build report lists every shield, with its reason, and any quill's unchecked IR (D79).
- Everything outside a shield stays fully checked; only what a shield gives back has to be valid Jernal.

This follows a general rule for where things go: the opening line says what something is, the part that changes how
it's used (a function's parameters, result and `fails`, D48); the top of the body describes it or says what it
promises (`labels`, `defaults`, `requires`, `ensures`, D42, and a shield's `reason`). From Cyborg's shield, as Cyborg's
design session described it on 2026-11-14. The owner said "Why the fuck is `:` there, and not behind `"`?" and "Idk,
failures are in a function's header"; Claude proposed that rule; the owner chose: "fair, yea". (Owner, 2026-11-14)

**D81. A standard, kept with every decision.** `standard/` says what Jernal is, by topic, without the history, with
one file per chapter and a last chapter listing every open question. `DECISIONS.md` stays the log of how each part was
chosen. Every decision updates both, in the same commit. JernComp and JernOrac are built from the standard, and
anything in its "Not decided yet" chapter gives `NotDesignedYet`. The owner asked "Should we have a standard?"; Claude
proposed this; the owner chose: "yes". (Owner, 2026-11-14)

**D82. `Float` is IEEE binary64, and `Decimal` and `Rational` are built in.** There is one float type, `Float`, which
is IEEE 754 binary64; NaN and infinity exist, as IEEE says. There are no float kinds for now. Stable floats, the same
bits on every machine, come later if ever, as `f64.stable`. `Decimal` and `Rational` are built in. Decimal's size and
Rational's representation are not decided yet. Cyborg instead has three float kinds and no built-in decimal, as its
design session described on 2026-11-14. The owner asked "You know how big stable floats are, right?", and chose:
"(a). There's just `Float` which is IEEE Binary64. `Decimal` is built in, but what IEEE size? And Rationale should
also be built-in. Stable floats come later, if ever (as `f64.stable`)". (Owner, 2026-11-14)

**D83. `Decimal` is decimal128, and `Rational` is arbitrary-size.** Settles D82's open questions. `Decimal` is IEEE 754
decimal128: 34 significant digits, exponents up to about ±6144. `Rational` is an exact fraction whose numerator and
denominator are arbitrary-size integers, so it never overflows. Claude proposed both; the owner chose: "yes yes".
(Owner, 2026-11-14)

**D84. `~` marks a literal its type can't hold exactly.** A number literal that the type it lands in can't hold exactly
must be written with `~` in front, and one it can hold exactly must not. The compiler checks both ways.

```
let $a: Float = 0.5          // exact in binary
let $b: Float = ~0.1         // inexact, so it says so
let $c: Float = 0.1          // refused, fix: `~0.1`
let $d: Float = ~0.5         // refused: 0.5 is exact
let $e: Decimal = 0.1        // exact in decimal
let $f: Rational = 0.1       // exact as 1/10
```

- The type decides: `0.1` is inexact as a `Float` but exact as a `Decimal` or `Rational`.
- A `Decimal` literal with more than its 34 digits needs `~` too.
- `Int` literals never need it; one that doesn't fit is a `CompileTimeError`.
- A negative is written `~-0.1`.
- `~` covers literals only, not calculations that round.

This is Cyborg's `~` (its D59), as Cyborg's design session described on 2026-11-14; the owner proposed it there.
Claude proposed it for Jernal's types; the owner chose: "yes". (Owner, 2026-11-14)

**D85. `Int / Int` is an exact `Rational`, and integer division is written out.** Dividing two integers with `/` gives
the exact `Rational`, never a silently truncated integer: `7 / 2` is `7/2`, and `1 / 3` is `1/3`. Getting back to an
`Int` says how to round, with `as.trunc`, `as.floor` and the like. Integer division has no bare form: `div.trunc`,
`div.floor`, or `div.exact`, which fails if there's a remainder, with `mod.trunc` and `mod.floor` for the matching
remainder. `Float / Float` gives a `Float`, and `Decimal / Decimal` a `Decimal`, each rounded to its own type.

```
let $half: Rational = 7 / 2
let $n: Int = (7 / 2) as.trunc Int           // 3
let $m: Int = 7 div.floor 2                  // 3
let $r: Int = -7 mod.floor 2                 // 1
```

The integer division and remainder words are Cyborg's (its D48, D97), as Cyborg's design session described on
2026-11-14. The full list of `as` rounding words, and what `div.exact` does per build mode, are not decided yet. Claude
proposed `7 / 2` as a `Rational`; the owner chose: "Oh I love 7 or 2", taken as the exact `7/2`. (Owner, 2026-11-14)

**D86. `*` multiplies, `( )` groups in maths, and precedence follows school maths.** The arithmetic operators are `+`,
`-`, `*` and `/` (D85), with the written-out `div.…` and `mod.…`. `x` stays an ordinary name, so `$point.x` needs no
`my::`. `( )` groups in maths, the one exception to "`( )` runs" (D15). Precedence, tightest first: calls and `.`, then
unary `-`, then `*`, `/`, `div.…` and `mod.…`, then `+` and `-`, then comparisons, then `not`, `and`, `or`.

```
let $area: Int = ($w + 2) * $h
```

Cyborg writes `x` for multiply, and has the same grouping exception and precedence (its D116), as Cyborg's design
session described on 2026-11-14. Claude proposed `*`, grouping as the one exception, and school maths precedence; the
owner said: "That means Fuck it, motherfucker", taken as yes to all three. (Owner, 2026-11-14)

**D87. D86 was never approved, and there is no `/`.** D86 recorded "That means Fuck it, motherfucker" as approval of
`*`, maths grouping and precedence; it wasn't, so D86 is withdrawn and all three are undecided again. D85's use of `/`
is withdrawn too: Jernal has no `/` operator. How dividing is written, and how a `Rational` like 7/2 is made, are not
decided yet. D85's written-out `div.trunc`, `div.floor`, `div.exact`, `mod.trunc` and `mod.floor` are not affected. The
owner said: "Let me be clear here: No `/`, and I didn't approve the last msg". (Owner, 2026-11-14)

**D88. Dividing is `div`, and on integers it says which kind.** Settles how dividing is written after D87. Integer
division has four kinds, and a bare `div` on integers is refused, listing them:

```
7 div.trunc 2        // 3: rounds toward zero
-7 div.floor 2       // -4: rounds down
6 div.exact 2        // 3; with a remainder, it fails
7 div.rational 2     // 7/2, an exact Rational
7 div 2              // refused: say which
```

On `Float`, `Decimal` and `Rational`, there's one sensible answer, so a bare `div` is used, and the result stays in the
same type: a `Float` rounded to nearest as IEEE says, a `Decimal`, or an exact `Rational`.

```
7.0 div 2.0          // 3.5
```

`mod.trunc` and `mod.floor` stay as in D85. The owner said: "Say it, `div.` what"; Claude proposed this; the owner
chose: "yes". (Owner, 2026-11-14)

**D89. `x` multiplies, and its narrowed forms are `times.`** Multiplying is `x`: `$w x $h`. When multiplying needs a
narrowing, such as for overflow on purpose, it's written as `times.` followed by the kind, as in `times.wrap`. `*` isn't
used for multiplying, since it already marks a handler that can jump (D48). As a built-in word, `x` follows D63: a
function named `x` is `my::x`. A field named `x` is exempt, since it only appears after a `.` or in a struct's
declaration, where it can't be read as multiplying: `$point.x` needs no `my::`. Which `times.` kinds exist is not
decided yet. Cyborg also multiplies with `x`, as its design session described on 2026-11-14. The owner asked "How in
the tarnational fuck would $point.x not be possible?" and "Isn't `*` for handlers breaking control flow?", and chose:
"`x`, and then when it needs narrowing, you could do `times.`". (Owner, 2026-11-14)

**D90. Maths precedence, and `( )` groups where maths gives no order.** Operators bind the way school maths says,
tightest first: calls and `.`; unary `-`; `x`, `div.…` and `mod.…`; `+` and `-`; comparisons; then `not`, `and`, `or`.
`( )` groups in maths, the one exception to "`( )` runs" (D15). Where maths gives no order between two operators, such
as bit operators mixed with anything else, the code must group with `( )`, and leaving it out is refused.

```
let $a: Int = 2 + 3 x 4            // 14
let $b: Int = (2 + 3) x 4          // 20
if $x < 10 and $done:              // ($x < 10) and $done
```

This is Cyborg's (its D116), as Cyborg's design session described on 2026-11-14. Replaces the withdrawn D86's grouping
and precedence. The owner chose: "maths precedence, if no, group with `()`". (Owner, 2026-11-14)

**D91. Converting between number types.** Conversions use `as`, and say what they do whenever there's a choice:

- A conversion that always fits is a plain `as`.
- One that might not fit is a plain `as` with a check; a value that doesn't fit is a `RuntimeError` (D53).
- Overflow on purpose is written out: `as.wrap` keeps the low bits, and `as.saturate` sticks at the ends.
- From `Float`, `Decimal` or `Rational` to an integer type, the rounding is always said: `as.trunc`, `as.floor`,
  `as.ceil`, `as.round.even`, `as.round.away`, or `as.exact`, which is a failure that can be handled if anything would
  be lost. There's no bare rounding, since ties are a real choice.
- Into `Float`, a value rounds to nearest.

```
let $big: Int = $small as Int
let $small: i32 = $big as i32
let $low: u8 = $big as.wrap u8
let $capped: u8 = $big as.saturate u8
let $f: Float = $n as Float
let $i: Int = $f as.round.even Int
let $exact: Int = $r as.exact Int ?? 0
```

Settles D85's open list of rounding words. This is Cyborg's (its D424, D425), as Cyborg's design session described on
2026-11-14. Claude proposed it; the owner chose: "yea". (Owner, 2026-11-14)

**D92. Overflow on purpose: `plus.`, `minus.` and `times.`** Wrapping or capping on purpose is written as a narrowing
of the operation's word: `plus.wrap`, `plus.saturate`, `minus.wrap`, `minus.saturate`, `times.wrap`,
`times.saturate`. They behave the same in every build mode, `FinalPerf` included. On `Float`, `.wrap` is refused, and
overflow follows IEEE (D82).

```
let $h: u32 = $h plus.wrap $byte
let $vol: u8 = $vol plus.saturate 10          // sticks at 255
let $left: u8 = $left minus.saturate 1        // sticks at 0
let $mix: u64 = $a times.wrap 31
```

Settles D89's open `times.` kinds. This is Cyborg's (its D294, D295), as Cyborg's design session described on
2026-11-14. Claude proposed it; the owner chose: "yea". (Owner, 2026-11-14)

**D93. Sized types: any integer width, gated unless it's a power of two, and four float sizes.** Integers come in any
width LLVM allows, from 1 to 8,388,607 bits, signed (`i…`) and unsigned (`u…`). A width that's a power of two is
written bare: `u1`, `u4`, `i8`, `i64`, `u128`, `u256`, `u512`. Any other width needs the `not_two_pow.` gate, and a bare
one is refused, so a typo such as `i46` for `i64` can't slip through. Floats are `f16`, `bf16`, `f32` and `f64`, where
`f64` is `Float` (D82). Widths other than 8, 16, 32, 64 and 128 are slower, since the CPU works in those; huge ones are
much slower to compute and to compile.

```
let $flag: u1 = 1
let $hash: u256 = $sha
let $pixel: not_two_pow.u24 = $rgb
let $odd: i46 = 0                       // refused: 46 isn't a power of two
let $half: f16 = 0.5
```

The owner asked for "`i8` to `i128`, `u8` to `u128`, `f16` to `f64`?", "`bf16` too? And doesn't LLVM somehow support every
fucking int?", "where the uck is u8000000", suggested gating odd widths ("`let x: not_std.i80000`?"), asked "Does
`u256` count as odd", proposed "`not_two_pow.`", and chose: "yeA". (Owner, 2026-11-14)

**D94. `div.exact` fails the same way in every mode but `UB++`.** `div.exact` with a remainder is a failure (D85), so
it fails, and can be handled, in `Interp`, `Working`, `FinalSafe` and `FinalPerf` alike (D71). In `UB++`, where anything
wrong is undefined behaviour (D70), a remainder is undefined behaviour too. Settles D85's open question. Claude proposed
the same behaviour in every mode; the owner said: "Nope, because `UB++`". (Owner, 2026-11-14)

**D95. Strings escape only `\"` and `\\`, and hold no layout characters.** Inside a string, `\` is always special: `\"`
is a quote and `\\` is a backslash, and any other `\` followed by a character is refused. There are no layout
characters in plain strings, such as a newline or a tab: they come with the formatting tool, which isn't designed yet
(D21). `println` already ends its line, so several lines means several `println`s.

```
println("She said \"hi\"")
println("C:\\Users\\tankun")
println("a\nb")                       // refused: layout comes with the formatting tool
```

The owner said "So, `\"` escapes a char, while `\n` adds format? Diabolical" and "We don't have a fucking format print
yet, why are you putting format into a non format print, my ass", asked "What is `\\` for?", turned down a backslash
that's only special before `"` ("Fuck no"), and chose: "A". (Owner, 2026-11-14)

**D96. `Bool`, and comments: `//`, `///` and `comment name:`.** `Bool` is the type of `true` and `false`. A `//` comment
runs to the end of the line. A `///` comment is documentation for the declaration below it. A longer comment is a named
block, `comment name:` ... `end comment name`, whose inside is text, not code, until its own `end` line.

```
let $done: Bool = true

/// Adds two numbers.
fn add[$a: Int, $b: Int] -> Int:
    return $a + $b             // a line comment
end fn add

comment old_version:
    fn add[$a: Int, $b: Int] -> Int:
        return $b + $a
    end fn add
end comment old_version
```

Claude proposed `Bool` and `//`; the owner chose: "Yes, and `///` doc comments, and `comment name:`, `end comment
name`". (Owner, 2026-11-14)

**D97. Tagged unions and `match`.** A tagged union is a block of cases, one per line; a case's data goes in `[ ]` with
labelled fields. It's always written `union.tagged`; a bare `union` is refused. An enum is a union whose cases carry no
data. Cases are narrowings of the type, and a value is built like a struct.

```
union.tagged Status:
    ok
    failed[code: Int]
end union.tagged Status

let mut $s: Status = Status.failed[code = 3]

match $s:
    case failed $f:
        println("failed: " $f.code as String)
    case ok:
        println("worked")
end match

if $s: Status.failed:
    println("code " $s.code as String)
end if
```

- `match` must cover every case; a missing one is refused, so adding a case later makes every `match` handle it.
- Arms use the case's short name, as `otherwise` does (D48); `case failed $f:` names its data.
- `if $value: Type.case:` tests which case a value is. Inside, the compiler knows the case, so its fields can be read;
  outside, they can't. That knowledge ends at a `change` to the value: anything after it that relies on the case is
  refused, with a `because:` pointing at the change.

Not decided yet: whether `match` gives a value, a catch-all arm, guards, matching on integers, strings and ranges, and
a naming form of the test. This is Cyborg's (its D9, D33, D104, D139), as Cyborg's design session described on
2026-11-14, with short case names in arms. Claude proposed it; the owner chose: "yea". (Owner, 2026-11-14)

**D98. `match` is a statement.** `match` gives no value. A value from a `match` comes through `decl` and `assign`
(D34), which make sure every arm gives it exactly once. This keeps D19 (an expression never spans lines) and D24
(results are written out, never "the last line").

```
decl $label: String
match $s:
    case ok:
        assign $label = "fine"
    case failed $f:
        assign $label = "error " $f.code as String
end match
```

As in Cyborg, as its design session described on 2026-11-14. Claude proposed it; the owner chose: "A". (Owner,
2026-11-14)

**D99. No catch-all in `match`, and reusable sets of arms for unions.** `match` has no catch-all arm: every case is
always covered, so adding a case to a union makes every `match` that needs it refuse until it's handled. Instead, a
named set of arms for a union's cases can be written once and reused in many `match`es, like `fam.handler` (D48) for
failures; at each use, it must still cover every case. How such a set is declared and used is not decided yet. Picking
out a few cases is done with the case test, `if $x: Type.case:` (D97). Radium's design session described Radium's
`otherwise` and handlers as being for failures only, with no catch-all in `match`, and suggested reusable arm sets; the
owner had said: "I think Radium had `otherwise` blocks that could be used with pre-made handlers". Claude recommended
no catch-all, with arm sets later; the owner asked "What do you recommend?", and chose: "D". (Owner, 2026-11-14)

**D100. Arm sets are `fam.handler`s, used with `match $x with ...`.** Settles D99's open form. The same `fam.handler`
(D49) holds arms for a union's cases as well as for failures; a handler is checked at each use against what that use
needs: the failures still possible for `otherwise`, or every case of the union for `match`. `match $x with
family.handler` is a one-line `match` using a set. A set that can `return` or `break` is used with D48's `*` mark. A
`match` is either written out or one set, never a mix.

```
fam.handler key_actions:
    handler basic:
        case enter:
            submit()
        case escape:
            cancel()
        case tab:
            next_field()
    end handler basic
end fam.handler key_actions

match $key with key_actions.basic
match $key with key_actions.*bail
```

Claude proposed it; the owner chose: "yes". (Owner, 2026-11-14)

**D101. `match` works on tagged unions and `Bool`, with no guards.** Since `match` covers every case with no catch-all
(D99), it works only on what has a short list of cases: tagged unions and `Bool`. Integers, strings and ranges use `if`
and `else if`. Arms have no guards, since a guarded arm would hide whether every case is covered; a check goes inside the
arm. The case test has no naming form, since `$s.code` can already be read inside `if $s: Status.failed:` (D97). This
settles everything D97 left open. Claude proposed it; the owner chose: "yes". (Owner, 2026-11-14)

**D102. Two or more type parameters are labelled, with `.type`.** A type with one type parameter writes it bare:
`List<Int>`. With two or more, each is labelled, and a label that takes a type ends in `.type`, since what it takes is a
type, not a value: `Map<key.type: String, val.type: Int>`. An unlabelled `Map<String, Int>` is refused. Replaces D64's
`Map<String, Int>`.

```
let $xs: List<Int> = [1, 2, 3]
let $ages: Map<key.type: String, val.type: Int> = ["Ann" => 30]
```

This is Cyborg's (its D25), as Cyborg's design session described on 2026-11-14. The owner asked "What the fuck, why do
we write `Map<String, Int>`" and "`val.type`?", and said: "`value: Int`. Int is a fucking type". (Owner, 2026-11-14)

**D103. Generics.** Functions and types can take type parameters in `< >`. A type parameter is written `?` and a
capitalized name, so it can't be mistaken for a real type, and always writes its requirement, even `Any` for none. A
type's labels (D102) come from its parameters' names: `?Left` is labelled `left.type:`. Calls never write the types:
they're worked out from the arguments, or from where the result goes, and if nothing says, it's refused. Generics are
compiled once per type they're used with, and the body is checked once, at the definition, against its requirements, so
a body using something its requirements don't promise is refused there.

```
fn largest<?Item: Ordered>[$a: ?Item, $b: ?Item] -> ?Item:
    if $a > $b:
        return $a
    end if
    return $b
end fn largest

struct Pair<?Left: Any, ?Right: Any>:
    first: ?Left
    second: ?Right
end struct Pair

let $big: Int = largest(3, 5)
let $p: Pair<left.type: Int, right.type: String> = Pair[first = 1, second = "a"]
```

Not decided yet: interfaces and how a type fits one, value parameters, and naming a type at a call. This is Cyborg's
(its D85, D89, D234, D239, D241), as Cyborg's design session described on 2026-11-14, with capitalized names. Claude
proposed it; the owner chose: "yes". (Owner, 2026-11-14)

**D104. No laws in interfaces, for now.** An interface lists operations only. What a type promises beyond them, such as
an order being transitive, goes in `///` documentation (D96). Laws can be added later, once there's a test tool or a
prover quill to check them; adding them won't change existing code.

```
/// Must be a total order: if a < b and b < c, then a < c.
interface Ordered<?Self>:
    includes Equatable
    op <[$a: ?Self, $b: ?Self] -> Bool
end interface Ordered
```

Cyborg's interfaces have laws (its D235). The owner asked "The fuck is proving laws?", "So, it's a runtime check?",
"Wait, why isn't it a runtime check?" and "Should we even have laws?"; Claude recommended none in v1; the owner chose:
"yea". (Owner, 2026-11-14)

**D105. Interfaces, type sets, and `satisfies`.** An `interface` lists operations with no code, and can include another
with `includes`. A `type_set` is a closed list of types that nothing can join later. Requirements combine with `and`,
and only an interface gives operations, so a body can't use `+` on a type-set-only parameter. A type fits an interface
only through a written line, `Type satisfies Interface`, never just by having the right operations; only the type's
package or the interface's package may write it. A type defines only `==` and `<`; `!=`, `>`, `at_least` and `at_most`
follow from them, so they can't disagree. Arithmetic is defined directly.

```
interface Ordered<?Self>:
    includes Equatable
    op <[$a: ?Self, $b: ?Self] -> Bool
end interface Ordered

type_set Whole:
    i32
    i64
end type_set Whole

Reading satisfies Ordered

fn smallest<?Item: Whole and Ordered>[$xs: List<?Item>] -> ?Item:
```

This is Cyborg's (its D87, D235 to D237, D240), as Cyborg's design session described on 2026-11-14, without laws
(D104). Claude proposed it; the owner chose: "yes". (Owner, 2026-11-14)

**D106. `pub`: always say how far.** A declaration without `pub` is seen only in its own file. `pub.pkg` shows it to its
package, and `pub.all` to everyone. A bare `pub` is refused, listing both, since there's a real choice and no hidden
default; searching for `pub.all` lists a package's whole public API. `pub.…` goes in front of the whole declaration;
`fn.pub` is refused, since visibility isn't what kind of function it is. Fields and family members each take their own
`pub.pkg` or `pub.all`. Closers don't repeat it.

```
fn helper[...]:                     // this file only
pub.pkg fn parse[...]:              // the package
pub.all fn get[...]:                // everyone
pub fn get[...]:                    // refused: say pub.pkg or pub.all

pub.all struct Reading:
    pub.all celsius: Int
    place: String
end struct Reading
```

- Using something that isn't visible is a `CompileTimeError` with `what:` and `why:` but no `fix:`, since making it
  visible is the other author's choice.
- A `pub.…` signature that mentions a less visible type is refused at the declaration.
- `pub.…` on `fn.main` is refused, with `fix: fn.main`, since nothing calls it.

Cyborg's levels (its D200, D413) are bare, `pub.pkg` and `pub`, and much of the rest is open there, as Cyborg's design
session described on 2026-11-14. The owner asked "Is `pub` vis to every is a sensible defau?", then "or just say it? I
mean, it's three letters", and chose: "yea". (Owner, 2026-11-14)

**D107. One `std`, organized by path, with `io` for the outside world.** Jernal has one standard package, `std`, with no
separate `os` package, since Jernal is never freestanding (D79). Its parts are organized by path, not by families:
`std::io` holds everything that talks to the outside world (`std::io::stdio` for standard input, output and error,
`std::io::file`, `std::io::net`), beside `std::env` for the program's surroundings, `std::time` and `std::math`. Code
writes short names (D59), so a path appears only in a clash or a `use`.

```
println("hi")                       // std::io::stdio::println
let $f: File = open($path)?         // std::io::file::open
let $args: List<String> = args()    // std::env::args
```

Cyborg splits `std` and `os`, and organizes by path. The owner asked "Which is where? Like, who owns io? And do we
really need to separate std and os? Jernal would never be freestanding", said "I don't know about using `io.`, instead
of making that in the path. Cyborg doesn't do that", asked "Doesn't `io` stand for input/output?" and "Define
`console`", pointed out that `inline.llvm_ir` is jargon too, and said: "You don't even write the path, bro". (Owner,
2026-11-14)

**D108. Command-line arguments come from `args()`.** `args()`, in `std::env`, gives the program's arguments as a
`List<String>`, without the program's own name, so `$args[pos: 1]` is the first argument. `program_path()` gives the
program's own path. An argument that isn't valid text is a failure of `args()`; the narrowing `args.raw()` gives raw
bytes instead. Settles D62's open question.

```
fn.main[]:
    let $args: List<String> = args()
    if $args.length == 0:
        println("usage: greet NAME")
        return early
    end if
    println("Hello, " $args[pos: 1])
end fn.main
```

The owner asked "how do you get CLI args"; Claude proposed this; the owner chose: "yea". (Owner, 2026-11-14)

**D109. `value.type`, not `val.type`.** Replaces D102's label: a map is `Map<key.type: String, value.type: Int>`. The
owner said: "change `val` to `value`". (Owner, 2026-11-14)

**D110. A version says `breaks` or `not_broken`.** Replaces D76's placeholder `same`. A release says `breaks` when it
changed or removed something `pub.all` (D106), and `not_broken` otherwise; Journey checks the word against what
actually changed, and refuses a release that claims `not_broken` but changed a `pub.all` item. A `need` may move to a
later `not_broken` release on its own, never to a `breaks` one.

```
ver 2026y-11m-14d not_broken
ver 2026y-11m-20d breaks
```

Claude proposed `breaks` / `adds` / `fixes`; the owner chose: "`breaks`, and `not_broken`". (Owner, 2026-11-14)

**D111. The manifest scopes a line with a prefix.** A line that applies only in some situations starts with a scope,
joined with `.`; the rest of the line is what it would be unscoped. There are no blocks or indentation, so every line
stands on its own. Scopes stack, strongest first. The scopes are `target.` (operating system or CPU) and `mode.` (build
mode, D70).

```
need std 2026y-11m-14d
target.windows need win_console 2026y-11m-01d
rule mut.never_changed refuse
mode.Working rule unused.variable warn
target.windows.mode.FinalPerf rule unused.variable refuse
```

Settles the manifest's nesting, following Cyborg's planned prefix, as its design session described on 2026-11-14.
Claude proposed it; the owner chose: "yes". (Owner, 2026-11-14)

**D112. No package features.** A `need` has no `with` and a package has no optional parts; an optional part is a
separate package. Claude proposed none for now; the owner said: "There's none, just don't fucking have it in there".
(Owner, 2026-11-14)

**D113. The manifest is checked and compiled.** `Journey.siml` isn't just read: it's checked, with errors in D10's
format, and compiled into the fastest form for the tools to load, recompiled whenever it changes. The time saved is
small, and it's done anyway. Claude described the manifest as only read; the owner said: "Nope, it's checked, and
compiles to the fastest thing, even though it saves less time than just not compiling it". (Owner, 2026-11-14)

**D114. `use` lives in the manifest, in a block per file.** A `.jern` file has no `use` lines. Short names chosen with
`use` (D60) go in `Journey.siml`, inside a block named after the file they're for, closed by a named `end`. D60's rules
for names stay. This is the first block in siml, alongside D111's one-line prefixes.

```
// Journey.siml
main.jern:
use time.seconds as seconds
use show.stored as "show_stored"
end main.jern
```

Not decided yet: whether a block can apply to every file. The owner said "nah, it's all in Journey, you say the file",
and, asked how: "you make a block." (Owner, 2026-11-14)

**D115. An `all` block gives every file a short name.** In `Journey.siml`, `all:` ... `end all` holds `use` lines for
every file in the package. A short name in `all` that a file's own block also gives is a clash, and Journey refuses
the manifest. Settles D114's open question.

```
all:
use time.seconds as seconds
end all

main.jern:
use show.stored as "show_stored"
end main.jern
```

Claude proposed `all`; the owner chose: "B, Journey won't compile if you clash with specific". (Owner, 2026-11-14)

**D116. A text `Journey.lock`, and a local compiled cache.** `Journey.lock` is plain siml, written by Journey and
committed: the exact version and content hash of every package in the build, dependencies of dependencies included, so
every machine builds the same code and a dependency change shows in review. Builds always use it, and versions move
only on `jern update`, never onto a `breaks` release (D110). D113's compiled form is a local cache instead: the
manifest, the lock, every file's resolved `use`, the rules and scopes, in the fastest machine-specific form. It isn't
committed, and it rebuilds itself whenever `Journey.siml` or `Journey.lock` changes, or JernComp updates.

```
// Journey.lock
locked std 2026y-11m-14d hash 9f3a…
locked http 2026y-11m-16d.2 hash 41c7…
```

The owner asked "Isn't `.lock` supposed to be the compiled version? Where's `use`?" and "Oh shit, it's not portable,
right?"; Claude proposed splitting the two; the owner chose: "Yes". (Owner, 2026-11-14)

**D117. Journey is written in Go for networking; JernComp owns siml and its errors; no compiled cache.** Replaces
D113's compiling and D116's local cache: `Journey.siml` and `Journey.lock` are read directly as text, since they're
small. JernComp, through `jern`, is the only program that reads and checks `Journey.siml`, and the only one that prints
errors in D10's format. Journey is written in Go and does the networking: resolving versions, downloading in parallel,
hashing, and writing `Journey.lock`. Journey gets the checked list of `need`s from `jern` as plain data; if the manifest
has errors, `jern` prints them and Journey stops. JernComp checks `Journey.lock` whenever it reads it. So there's one
siml parser and one error renderer, both in Rust. The owner said "It's a PM, maybe Go? I mean, I heard Go has good
networking", "don't PMs usually depend on optimizations (para, concur) and your own Wifi? Not "Does this have manual
memory"?" and "What if we remove the compiled cache? And error messages could just be a server? or something"; Claude
proposed splitting the jobs instead of a server; the owner chose: "Typ", confirmed as "Yup". (Owner, 2026-11-14)

**D118. No formatting tool for now.** There's no format print or formatting tool, so no decimal places, padding,
newlines or tabs in text for now (D21, D95). The owner said: "No format print for now." (Owner, 2026-11-14)

**D119. A float becomes text as its shortest digits, marked `~` when not exact.** `$f as String` gives the fewest digits
that read back as exactly the same float, with `~` in front when the float isn't exactly that decimal, so the text is
always a valid Jernal literal for the same float (D84). `$f as.stored String` gives every digit actually stored, which
is always exact. This applies to every float type (D93).

```
let $a: Float = 0.5
let $b: Float = ~0.1
println($a as String)                // 0.5
println($b as String)                // ~0.1
println(($b + ~0.2) as String)       // ~0.30000000000000004
println($b as.stored String)         // 0.1000000000000000055511151231257827021181583404541015625
```

CyborgPL prints the shortest digits with no mark, and its conversions must name the form, as its design session
described on 2026-11-14; multifinity's notes proposed the `~`. The owner said "But that means `as` lies? Which probably
isn't expected, tbh", asked "How does CyborgPL handle its store prints?" and "Isn't that silent rounding?", and chose:
"yup". (Owner, 2026-11-14)

**D120. `Bool` text, no float exponents for now, and float literals out of range are refused.** `true as String` is
`true`, and `false as String` is `false`. A float prints all its shortest digits with no exponent, such as `1e23` as
`100000000000000000000000`, until exponent literals are designed, since printed text is a valid literal (D119). A
float literal outside its type's range, such as `let $x: f16 = 70000.0`, is a `CompileTimeError`, as an integer literal
that doesn't fit is (D84). Claude proposed all three; the owner chose: "yes". (Owner, 2026-11-14)
