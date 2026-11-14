# 12. Not decided yet

Using anything here gives a `NotDesignedYet` error (rule 10). Each item moves into its chapter once decided.

## 12.1 Language core

- **Text:** what a struct looks like as text, and exponent literals (D120). There's no formatting tool for now (D118).
- **Generics:** value parameters, and naming a type at a call (D103).
- **A raw pointer type**, such as the `Ptr<u8>` in 11.2's example.

## 12.2 Functions and failures

- How `ensures` names the result (D42).
- A family member pointing at a function elsewhere (D45).
- Handlers taking arguments (D49).
- The name of the method that asks for a position as a failure, such as `$xs.get(pos: $p)` (D53).

## 12.3 Tools and packages

- Debug information per build mode.
- Threads, and whether changing shared data needs a shield (D79).

## 12.4 Quills and units

- The quills' actual interface and how it's versioned (D77).
- Units' placeholder words: `offset`, `with`, `fam.prefix`, `decibels of` (D58).
