# 12. Not decided yet

Using anything here gives a `NotDesignedYet` error (rule 10). Each item moves into its chapter once decided.

## 12.1 Language core

- **`Bool`:** its name and its values (`true`, `false`).
- **Comments:** `//` is used in every example, but isn't decided.
- **String escapes**, such as a newline or a quote inside a string.
- **Text:** what a `Bool`, a `Float` or a struct looks like as text, and the formatting tool for things like decimal
  places (D21).
- **Tagged unions, enums and `match`.**
- **Generics and interfaces:** how user code declares them.
- **`pub`:** what a package or file shows, on functions, families, their members and struct fields.
- **A raw pointer type**, such as the `Ptr<u8>` in 11.2's example.

## 12.2 Functions and failures

- How `ensures` names the result (D42).
- A family member pointing at a function elsewhere (D45).
- Handlers taking arguments (D49).
- The name of the method that asks for a position as a failure, such as `$xs.get(pos: $p)` (D53).

## 12.3 Tools and packages

- How a file or package is named on the command line, and whether `jern comp --Interp` is refused (D74).
- The manifest: nesting, features, the lockfile, and the real word for `same` (D76).
- Debug information per build mode.
- Command-line arguments, which will come from a package (D62).
- Threads, and whether changing shared data needs a shield (D79).

## 12.4 Quills and units

- The quills' actual interface and how it's versioned, what "verified" means, and whether quills must keep builds
  reproducible (D77).
- Units' placeholder words: `offset`, `with`, `fam.prefix`, `decibels of` (D58).
