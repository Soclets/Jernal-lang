# The Jernal standard

This is what Jernal is, by topic, without the history. [`DECISIONS.md`](../DECISIONS.md) is the log of how each part
was chosen, with the owner's words; each section here names the decisions it comes from, such as (D19). When the two
disagree, the newer decision wins, and this standard gets fixed to match.

Only Jernal Design Claude edits the standard (rule 12). Every new decision updates `DECISIONS.md` and the standard in
the same commit (D81). JernComp and JernOrac are built from this standard, and anything listed in
[chapter 12](12-not-decided.md) gives a `NotDesignedYet` error (rule 10).

| Chapter | |
|---|---|
| [1. Syntax](01-syntax.md) | lines, blocks, names, brackets, spacing |
| [2. Values and types](02-types.md) | numbers, strings, lists, maps, structs, aliases, units |
| [3. Variables](03-variables.md) | `let`, `mut`, `baked`, `decl`, `shadow`, `change`, `give`, `copy` |
| [4. Expressions and control flow](04-control.md) | comparisons, logic, joins, indexing, `if`, loops, ranges |
| [5. Functions and families](05-functions.md) | functions, narrowings, headers, methods, `fam.fn`, versions, `fn.main` |
| [6. Failures](06-failures.md) | `fails`, `fail`, `?`, `??`, `otherwise`, handlers |
| [7. Checks and error messages](07-errors.md) | compile-time and runtime checks, messages, exit codes, recovery |
| [8. Memory](08-memory.md) | the garbage collector, `must_give`, deep `copy` |
| [9. Packages and names](09-packages.md) | the manifest, Journey, short names, clashes, `use`, `my::` |
| [10. Tools and build modes](10-tools.md) | JernComp, JernOrac, JernGC, `jern`, build modes |
| [11. Shields and quills](11-shields-quills.md) | unchecked code, compiler extensions, Dialects |
| [12. Not decided yet](12-not-decided.md) | every open question |
