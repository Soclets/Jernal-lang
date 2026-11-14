# 5. Functions and families

## 5.1 A function

Parameters go in `[ ]`, `-> Type` gives the result, and leaving it out means the function returns nothing (D24). A
result is given with `return`, written out. The closer repeats the name.

```
fn add[$a: Int, $b: Int] -> Int:
    return $a + $b
end fn add
```

A function that returns nothing ends at its `end`. Leaving before the end says `return early` (D26). A function with a
result always uses `return $value`, wherever it is.

```
fn greet[$name: String]:
    if $name == "":
        return early
    end if
    println("Hi " $name)
end fn greet
```

## 5.2 Narrowings on `fn`

What kind of function it is goes on `fn` after a dot, strongest first; the wrong order is refused, with the right one
as the fix. The closer repeats everything (D41).

- `fn.pure`: the same input always gives the same output, and nothing else changes or is seen; no I/O, and only pure
  functions are called.
- `fn.pure.baked`: pure, and can also run while compiling, for a `let baked`.
- `fn.main`: where the program starts (5.9).

```
fn.pure.baked seconds_in[$days: Int] -> Int:
    return $days x 86400
end fn.pure.baked seconds_in

let baked $week: Int = seconds_in(7)
```

## 5.3 The top of a body

Before any code, a body may say how to call it and what it promises, in this order (D42):

- `labels`: which parameters are written with a label at the call. Unlabelled arguments come first, in order.
- `defaults`: a labelled parameter's value when the call leaves it off.
- `requires` and `ensures`: contracts, checked at runtime (chapter 7).

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

A function's failures go on its opening line, after the result (chapter 6).

## 5.4 Methods

Values have methods, called with a dot, so steps read left to right (D40). Plain functions stay for what doesn't belong
to a value, such as `println` and `now`.

```
let $clean: String = $text.trim().upper()
```

A method is declared in its type's family (5.5): a function whose first parameter is `$self` of that type. A method that
changes the value says `mut $self` in its declaration; its calls are written plainly, and calling it on a value that
can't change is refused (D43). A plain `$self` can't be changed inside the method.

## 5.5 Families: `fam.fn`

A `fam.fn` block holds things that belong under one name (D45):

1. a function and its narrowings and presets,
2. a group of related functions,
3. a type's makers and methods.

Inside `fam.fn <family>`, members are written short, after a keyword, and each one's full name is `<family>.<name>`; a
function named `<family>` itself is the family's own, called as `<family>(...)` (D45, D49). A narrowing on `fam.fn`, such as `fam.fn.pure`, applies to
every member.

```
fam.fn.pure geometry:
    fn area[$w: Int, $h: Int] -> Int:            // geometry.area(3, 4)
        return $w x $h
    end fn area
end fam.fn.pure geometry

fam.fn Reading:
    fn new[$celsius: Int] -> Reading:            // Reading.new(20)
        return Reading[celsius = $celsius]
    end fn new

    fn warm_up[mut $self: Reading, $by: Int]:    // $r.warm_up(by: 2)
        labels [$by as by]
        change $self.celsius = $self.celsius + $by
    end fn warm_up
end fam.fn Reading
```

A type has exactly one family, in the same place as the type; a second `fam.fn` with the same name is refused (D47). To
add helpers to a type someone else wrote, write a separate family of plain functions. Plain `fn` stays for single
functions, and turning one into a family later changes no calls (D45).

## 5.6 Function narrowings and presets

After a function's name, `.` picks a kind of it (D44, D45). In a family named after a function:

- `preset name [$param = value]` fills in some of the family function's labelled arguments, with no body. Presets stack,
  one per `.`; a chain that sets one parameter twice is refused.
- `fn name[...]` inside the family is a narrowing with its own code, for a kind that works too differently to be a
  setting.

```
fam.fn show:
    fn show[$x: Float, $digits: Digits] -> String:    // $x.show()
        labels [$digits as digits]
        defaults [$digits = shortest]
        ...
    end fn show

    preset stored [$digits = all]                      // $x.show.stored(), the same as show(digits: all)

    fn hex[$x: Float] -> String:                       // $x.show.hex(), its own code
        ...
    end fn hex
end fam.fn show
```

## 5.7 Versions

One name can have several parameter lists, in a `versions` block inside a family; the compiler picks one by the number
of arguments and their exact types (D46). Versions exist only inside a family. Two versions that could take the same
call are refused, and so is a default that would make them overlap.

```
fam.fn area:
    versions area:
        [$side: Int] -> Int:
            return $side x $side
        end version
        [$w: Int, $h: Int] -> Int:
            return $w x $h
        end version
    end versions area
end fam.fn area

area(3)         // 9
area(3, 4)      // 12
```

## 5.8 Generics

Functions and types can take type parameters in `< >` (D103). A type parameter is written `?` and a capitalized name,
and always writes its requirement, even `Any` for none. Calls never write the types: they're worked out from the
arguments, or from where the result goes. Generics are compiled once per type they're used with, and the body is checked
once, at the definition, against its requirements.

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
let $p: Pair<left: Int, right: String> = Pair[first = 1, second = "a"]
```

A type's labels come from its parameters' names: `?Left` is labelled `left:` (D103, D132).

An `interface` lists operations with no code, and can include another with `includes` (D105). It has no laws; promises
go in `///` documentation (D104). A `type_set` is a closed list of types. Requirements combine with `and`, and only an
interface gives operations. A type fits an interface only through a written `<type> satisfies <interface>` line, which only
the type's package or the interface's package may write. A type defines only `==` and `<`; `!=`, `>`, `at_least` and
`at_most` follow.

```
/// Must be a total order: if a < b and b < c, then a < c.
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

## 5.9 `fn.main`

A program starts at its one `fn.main` (D62). It takes no parameters and returns nothing, ending at `end fn.main` or with
`return early`. A program with none, or with two, is refused. A plain `fn main` is refused, with `fix: fn.main`; a
function really named main is `fn my::main` (chapter 9).

```
fn.main[]:
    println("Hello, World!")
end fn.main
```
