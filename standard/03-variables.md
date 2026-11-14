# 3. Variables

## 3.1 Declaring

Every new name says how it's made and whether it can change (D5, D34, D35, D36, D43):

| | Can't change | Can change |
|---|---|---|
| with a value | `let $x: Int = 1` | `let mut $x: Int = 1` |
| value comes later | `decl $x: Int` | `decl mut $x: Int` |
| reusing an existing name | `shadow $x: Int = 1` | `shadow mut $x: Int = 1` |

A `let` always writes its type. `let baked` declares one whose value must be known when compiling; "baked" is Jernal's
word for compile-time things (D5).

```
let $x: Int = 1000
let mut $total: Int = 0
let baked $week: Int = seconds_in(7)
```

## 3.2 `let` freezes the inside

A value that can't change can't be reassigned, and nothing inside it can change either: a `let` list never gains or
loses an item (D6). This is how values work in maths.

## 3.3 `decl` and `assign`

`decl` declares a variable with its type and no value. `assign` gives it its first value, exactly once on each path
through the code (D34). Reading it before every path has assigned it is refused, so nothing can read it empty. After
that it acts like a `let`, or, with `decl mut`, like a `let mut` (D35). `assign` on something that already has a value
is refused, with `fix: change`.

```
decl $label: String
if $hot:
    assign $label = "hot"
else:
    assign $label = "cold"
end if
```

## 3.4 `shadow`

`shadow` gives an existing name a new value, which may have a new type; from then on the name means the new one (D36).

- Declaring an existing name with `let` or `decl` is refused, with `fix: shadow`.
- `shadow` on a name that doesn't exist is refused, with `fix: let`.
- It works in the same block or an inner one; in an inner block, the old name comes back after the block's `end`.
- It works after `give`, which retires the old name.

```
let $total: Int = 5
shadow $total: String = $total as String
```

## 3.5 `change`

Every update starts with `change`: a whole variable, one field or one item (D33). A bare `$x = ...` is refused, with
`fix: change $x = ...`, and `change` on something that can't change is refused. There is no `+=`, `-=`, `*=` or `++`
(D32): an update reads in order, as `$count + 1`.

```
let mut $count: Int = 0
change $count = $count + 1
change $user.name = "Tankun"
change $xs[pos: 3] = 10
```

A method that changes the value it's called on is called plainly; see chapter 5.

## 3.6 `give` and `copy`

The garbage collector does all the memory work; `give` and `copy` exist so a reader can see when two names could share
something that changes (D7, D22).

- Handing off something whose inside can change, such as a `let mut` list or struct, says `give` or `copy`.
- `give $a` moves it to the new name and retires `$a`, copying nothing. Using a name after it was given is refused when
  compiling; a name that might have been given, such as inside an `if` or a loop, counts as given.
- `copy $a` makes a separate one, and both stay usable. It copies right away, where it's written (D50), and it's deep:
  everything that can change is duplicated, all the way down, while frozen parts are shared, so `copy` of a `let`
  value costs nothing (D52).
- Plain values need no word: numbers, strings, and anything frozen.
- A missing word gives the error "say `give` or `copy`".
- A value with a `must_give` part inside can't be copied (D52).

```
let mut $a: List<Int> = [1, 2, 3]
let mut $b: List<Int> = copy $a        // a separate list
let $c: List<Int> = $a                 // refused: say give or copy
let $d: List<Int> = give $a            // $a is retired, and the list is now frozen under $d
let $n: Int = $x                       // plain values need no word
```

There is no `Lend`, no lifetimes and no borrow checker (D7).
