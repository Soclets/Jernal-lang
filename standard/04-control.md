# 4. Expressions and control flow

## 4.1 Comparisons

| Write | Means |
|---|---|
| `==`, `!=` | equal, not equal |
| `<`, `>` | less, greater, with a space on both sides (1.5) |
| `at_least`, `at_most` | greater or equal, less or equal |

`>=` and `<=` are refused, with the word as the fix, and `=` in a condition is refused, with `fix: ==` (D27).

## 4.2 Logic

Conditions combine with `and`, `or` and `not` (D28). `and` and `or` short-circuit: the right side runs only if it can
still change the answer. `and.both` and `or.both` always run both sides. `&&`, `||` and `!` are refused, with the word as
the fix.

```
if $age at_least 18 and $has_ticket:
if not $done:
if check_a() and.both check_b():
```

## 4.3 Joining strings

Values written next to each other are joined into one string, everywhere, with no operator; there is no interpolation
(D20). A join holds only strings, variables, fields and `as` (D23). Anything that isn't a `String` is converted
explicitly with `as String`, which applies only to the one value right before it (D21, D23). Operators such as `+` are
refused inside a join, with a `fix:` that names a step first.

```
println("Hello, " $name)                   // Hello, Tankun
println("Hi, " $user.name "!")
println("Age: " $age as String)
println("Age: " $age)                      // refused, fix: `$age as String`
let $total: Int = $a + $b
println("Total: " $total as String)
```

`println` is an ordinary function that takes a `String`, with no formatting options (D21).

## 4.4 Indexing

An index always says how it counts: `pos:` counts from 1, and `offset:` from 0 (D17). A bare index is refused. A
position outside the list is a check (chapter 7).

```
$xs[pos: 1]       // the 1st item
$xs[offset: 0]    // the same item
$xs[1]            // refused: say pos: or offset:
```

## 4.5 `if`

Further branches are `else if` and `else:`, and one `end if` closes the chain (D29).

```
if $age < 13:
    println("kid")
else if $age < 18:
    println("teen")
else:
    println("adult")
end if
```

## 4.5a `match` and the case test

`match` must cover every case of a tagged union; a missing one is refused (D97). Arms use the case's short name, and
`case name $f:` names its data.

```
match $s:
    case failed $f:
        println("failed: " $f.code as String)
    case ok:
        println("worked")
end match
```

`match` is a statement and gives no value; a value from it comes through `decl` and `assign` (D98).

`if $value: Type.case:` tests which case a value is. Inside, its fields can be read; outside, they can't. That
knowledge ends at a `change` to the value: anything after it that relies on the case is refused (D97).

```
if $s: Status.failed:
    println("code " $s.code as String)
end if
```

## 4.6 Loops

`for ... in` goes through something, and `while` runs while a condition holds; each closes with its own `end` (D30).
`break` leaves the innermost loop. There is no `continue`: an item is skipped by wrapping the work in an `if`.

A loop may have a name after `for` or `while`; its closer repeats it, and `break name` leaves that loop and every loop
inside it (D31).

After the list in a `for`, `at pos $p` gives each item's position counting from 1, and `at offset $o` counting from 0
(D39).

```
for rows $row in $grid:
    for $cell in $row:
        if $cell == $target:
            break rows
        end if
    end for
end for rows

for $name in $names at pos $p:
    println($p as String ". " $name)        // 1. Ann, 2. Bob
end for

while $count < 10:
    change $count = $count + 1
end while
```

## 4.7 Ranges

A range is labelled: `from:` is required, then either `to:`, which includes the end, or `before:`, which stops before
it, then an optional `step_by:`, in that order (D37). There is no `..`.

```
for $i in range[from: 1, to: 5]:                  // 1, 2, 3, 4, 5
for $i in range[from: 0, before: 5]:              // 0, 1, 2, 3, 4
for $i in range[from: 0, to: 10, step_by: 2]:     // 0, 2, 4, 6, 8, 10
for $i in range[from: 5, to: 1, step_by: -1]:     // 5, 4, 3, 2, 1
```

- A range known when compiling that can never reach its end is refused; one only known while running runs zero times.
- A `step_by:` of 0 is a check.
- The loop's own variable can't be changed inside the loop.

## 4.8 `sum`

`$xs.sum()` is always exact: exact for integers, and for floats it rounds once at the end, like Python's `math.fsum`
(D38, D40). An empty list sums to `0`, and the result has the items' type.
