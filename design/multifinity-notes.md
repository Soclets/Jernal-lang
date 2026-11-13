# Notes from multifinity's chat

Collected by Claude in multifinity's chat, updated 2026-11-13 16:10, and passed to Tankun. Saved here unchanged.
These are notes, not decisions: only `DECISIONS.md` records what Tankun chose. Tankun's own words in them are marked as
such; the rest are proposals.

```
JERNAL: notes collected by Claude in multifinity's chat (updated Nov 13, 16:10)

STATUS
- Started as multifinity's design bait. On Nov 13 Tankun adopted it: "If I were to impl Jernal
  (yes, that's the name, I copied you, Mult)..."
- Name: no meaning, sounds like "journal" spelt wrong, like Lincoln Park -> Linkin Park. Soft, friendly,
  searchable, a good contrast to "Cyborg". Small risk: people may misspell it as "journal".
- Other names considered: Pulse, Synapse, Arrow, Lance, Plainly, Capsule, Sprout, Corvel, Tessa, Prova.
  Exo dropped (sounds low-level, "exokernel"). Avoid existing languages: Lumen, Dart, Nim, Crystal, Gleam,
  Odin, Vale, Roc, Wren, Mojo, Carbon, Hare. Nerve and Graft were already used in CyborgPL's brand folder.

PITCH
"Contained, Straight-to-Point, Easy-to-Start, and Progressive."
Proposed specialty (the "why not Go or Swift"): the maths is right, and it tells you when it isn't.

TANKUN'S SKETCH (Nov 13, "a sketch, might have wrongs")
// RFC 430-like naming enforcement
// GC
// use full path syntax only on clash
// config, imports, and stuff are handled by manifest
// So, code could be straight-to-point
// i32 style types are usable, just not here
fn main[]:
let $x: Int = 1000 // i64
var $total: Int = 0
let $name: String = "Tankun"
let $empty: String = empty // instead of "", because it looks finished
// implicit return void
println("Hello, $name") // to print literally that, use \$name
end fn main

Notes: `$` names reused for string interpolation, `\$name` to print literally. `empty` instead of "".

OPEN QUESTIONS
1. `fn main[]:` - by the `empty` logic, does `[]` look unfinished like `""`? Cyborg uses `[none]`.
2. Interpolation: only `$name`, or also `"$user.name"` / expressions (something like `${...}`)?
3. Money text like "Price: $5": literal, or does it need `\$5`?
4. `let` = can't change, `var` = can change? Cyborg uses `let mut`; using both could confuse.
5. Semicolons: optional? (Earlier snippet mixed them.)

V1 SCOPE (Tankun)
"I would do the compiler, GC, and basic stuff, and contracts. No units or stable floats yet."
Lesson from Cyborg (Tankun: "I rushed to compiler too quickly"; integer conversion was only decided in D424):
basics first, and write the core design down before building the compiler.

ARCHITECTURE (multifinity's proposal)
- LLVM through a mature toolchain, no Lyftar (Tankun wants to maintain little).
  In Rust: `inkwell`, or emit LLVM IR text and let clang finish.
- Custom GC (Tankun: fine with writing his own). The part that touches the compiler is finding roots:
  shadow stack first (simple, LLVM has a built-in strategy), statepoints + stack maps later if needed.
- Build modes:
  - FinalSafe
  - FinalPerf
  - FinalQuick (Go-like compiling). Note: LLVM is never Go-fast even at O0; Cranelift is the usual answer
    (Rust, fast compiling, used in TAKL), but it's a second backend to maintain, so maybe later.
  - UB++ (FinalShit spirit; in a GC language, probably dropping contracts and bounds checks)
  - Working (choose your own optimization level)
  - Interp (runs on the oracle: no compile, great for Easy-to-Start)
  Suggested v1: Interp + Working + FinalSafe; the rest later.

THE MATHS SPECIALTY (ideas, made-up syntax)
1. Exact decimals by default: `0.1 + 0.2` is 0.3 as a Decimal.
2. Inexact float literals must be marked `~`, and the compiler checks it:
     let $a: Float = 0.5      // ok, exact in binary
     let $b: Float = ~0.1     // ok, admits it's approximate
     let $c: Float = 0.1      // refused: 0.1 can't be exact as a Float
     let $d: Decimal = 0.1    // ok, exact
   Consistent with Cyborg's `~` for approximate literals.
3. Units with friendly literals: `5 km + 300 m`, `$trip / 2 h`, `5 km + 3 kg` refused. (Later, not v1.)
4. Division that doesn't lie: `7 / 2` gives 3.5 (or exact 7/2), never a silent 3; integer division is asked for.
5. Integers never wrap silently: they grow or stop with an error.
6. No lying rounding: rounding always says how (`round.half_up`, `round.half_even`, `round.down`);
   a bare `round` is refused. Decimals round exactly (1.005 to 2 places is 1.01).
7. No lying printing: printing an inexact float shows `~` (e.g. `~0.30000000000000004`), or you choose digits.
8. Extras: `20%` literal, correctly rounded sqrt/sin (CORE-MATH, like Cyborg).
Could absorb Numwah, Tankun's paused maths language.

IDE / LSP
- A language server reusing the compiler's checker shows the `~` problem while typing.
- One-click quick fix: "Add ~" or "Use Decimal". Better than silently auto-adding `~`, since noticing
  the approximation (and sometimes choosing Decimal) is the point.

PERF GUESS (speculation, no compiler yet)
Static types + compiled + GC: around Go / Swift / C# / Java overall. Plain number loops could get near C
through LLVM; object-heavy code depends on the GC, likely behind Go/Java until it matures; far faster than
Python/Ruby/Lua. ChatGPT's "Go-level" prediction was wrong for Cyborg (Rust-level) but probably right for Jernal.

EARLIER BITS (Nov 10-12, partly from a summary of this chat)
- `if x = 10` is invalid.
- `immut` and `const` are different things.
- `$` vs `#x` was discussed (to a kid `$` means dollar).
- Earlier snippet: `var x: Int = 1000; // i64`, `var xx: i32 = 1000`, `print("Hello, World!")`.
- Earlier ideas: sandboxed JIT, functions without writing their types, SPARK-proven Lua-replacement angle.
```
