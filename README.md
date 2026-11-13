# Jernal

Jernal is a programming language by Tankun Sriket: compiled, garbage-collected, and built to read the way you'd say it.

> **Status:** being designed. There's no compiler yet, so nothing here runs. Every choice so far is in
> [`DECISIONS.md`](DECISIONS.md), with the owner's own words.

## A taste

```
fn main[]:
    let $name: String = "Tankun"
    let mut $total: Int = 0
    for $i in range[from: 1, to: 3]:
        change $total = $total + $i
    end for
    println("Hello, " $name "! Total: " $total as String)
end fn main
```

## What it's like

- **Says how it counts.** Indexing is `$xs[pos: 1]` from 1 or `$xs[offset: 0]` from 0, never a bare number. Ranges say
  whether they include the end: `range[from: 1, to: 5]` or `range[from: 0, before: 5]`.
- **Reads in order.** Methods chain left to right (`$text.trim().upper()`), there's no `+=`, and comparisons you'd say
  as words are words: `at_least`, `at_most`, `and`, `or`, `not`.
- **Nothing happens behind your back.** `let` freezes a value inside and out, changes start with `change`, hand-offs
  say `give` or `copy`, and turning a value into text says `as String`.
- **Errors that know the fix.** Every error is shown at once, knock-on errors point back to their cause, and when there's
  exactly one fix, the message gives it. Each kind exits with its own code, counting down from 122.
- **Failures you can handle, checks you can't ignore.** A function lists what can fail (`fails [...]`), and callers
  pass it up with `?`, swap in a value with `??`, or handle each case with `otherwise:`. Bugs, like a false contract,
  stop the program; they never give a wrong answer.
- **One name, many kinds.** `fam.fn` groups a function with its narrowings (`show.stored`), presets and versions, a
  set of related functions, or a type's methods.
- **Progressive.** Everyday types like `Int` and `String` come first; sized types like `i32` are there when you need
  them, and `baked` runs things while compiling.

## Licences

- [`LICENSE`](LICENSE): Apache-2.0 WITH LLVM-exception, for the code. Programs you compile owe nothing.
- [`LICENSE-CC-BY-4.0`](LICENSE-CC-BY-4.0): CC BY 4.0, for this repo's writing: its Markdown files, including this
  README, `DECISIONS.md` and `RULES.md`. Credit them as
  `Jernal-lang GitHub repo text: https://github.com/Soclets/Jernal-lang`, say they're under CC BY 4.0, and say whether
  you changed them.
