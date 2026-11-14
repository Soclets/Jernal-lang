# 1. Syntax

## 1.1 Lines

A line break ends a statement, and there are no semicolons (D19). An expression never continues onto the next line; a
long one is split into named steps. The only exception is inside brackets: a call, list, map or declaration may break
between its items, and a comma after the last item is allowed (D64).

```
let $subtotal: Int = $price x $count
let $total: Int = $subtotal + $shipping

let $user: User = make_user(
    name: "Tankun",
    age: 30,
)
```

## 1.2 Blocks

A line that opens a block ends with `:`. The block closes with `end` followed by everything the opening said: the
keyword, its narrowings and its name, such as `end fn add`, `end fn.pure area`, `end if`, `end for rows`,
`end fam.fn Reading` (D24, D29, D31, D41). A named `end` tells the reader, and error recovery (D13), exactly which block
stops.

Inside a block, the first lines may describe it before any code: a function's `labels`, `defaults`, `requires` and
`ensures` (D42), a shield's `reason` and `pin` (D80). The general rule (D80): the opening line says what something is,
the part that changes how it's used; the top of the body describes it or says what it promises.

## 1.3 Names

- A variable's name starts with `$`: `$total`, `$user` (sketch).
- Types are capitalized: `Int`, `String`, `Reading`, `OpenFile` (D56). Sized types are lowercase: `i32`, `i64` (D25).
- Keywords are lowercase: `let`, `mut`, `fn`, `end`, `if`, `give`, `as` (D22).
- Functions, fields and narrowings are lowercase, with `_` between words: `first_word`, `celsius`, `fn.pure`,
  `String.utf8`, `Map.hash` (D56, D64).
- A field has no `$`; it's read through a variable: `$r.celsius` (D56).
- `.` picks something more specific: a family's member (`geometry.area`), a narrowing (`show.stored`, `fn.pure`), a
  field (`$r.place`) or a method (`$text.trim()`) (D40, D44, D45).
- `::` is a path: `http::get`, `pkg::get`, `my::main` (D59, D63).
- A name of the program's own that is also a built-in word is written with `my::` (chapter 9).

## 1.4 Brackets

- `( )` runs something: a call (D15). In maths, it also groups: `(2 + 3) x 4` (D90).
- `[ ]` describes or holds: parameters in a declaration, building a struct, a type's details, list and map literals,
  labelled indexing (D15, D17, D56, D64).
- `< >` fills in a type: `List<Int>`, `Map<key.type: String, value.type: Int>` (D18).

```
fn greet[$name: String]:       // [ ] describes what goes in
greet("Tankun")                // ( ) runs it
```

## 1.5 Spacing around `<` and `>`

`<` and `>` are both comparisons and type brackets, told apart by spaces (D18). A comparison has a space on both sides.
Type brackets stick to the name before them. Anything in between is refused, with the one fix shown.

```
$age < 18              // comparison
List<Int>              // type brackets
List<List<Int>>        // the >> is two closers, never a shift
$age<18                // refused, fix: `$age < 18`
List <Int>             // refused, fix: `List<Int>`
```

## 1.6 Emptiness

No parameters, no arguments and empty values are written with nothing inside: `fn.main[]:`, `now()`, `""`, `[]`
(D14, D64). There's no `[none]` and no `empty`. A comment such as `// none` may be added for readers.

## 1.7 Comments

A `//` comment runs to the end of the line. A `///` comment is documentation for the declaration below it. A longer
comment is a named block, `comment name:` ... `end comment name`, whose inside is text, not code, until its own `end`
line (D96).

```
/// Adds two numbers.
fn add[$a: Int, $b: Int] -> Int:
    return $a + $b             // a line comment
end fn add

comment old_version:
    ...
end comment old_version
```
