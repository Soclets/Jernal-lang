# 2. Values and types

## 2.1 Integers

`Int` is a 64-bit signed integer, `i64` (D54). It never wraps: going past its range is a check (chapter 7), except in
`FinalPerf`, where `+`, `-` and `*` wrap (D71). Sized types such as `i32` (a 32-bit signed integer) are all available
for whoever needs them (D25). Spelling out a default is always allowed: `i64` works wherever `Int` does (D64).

Which sized types exist, and how they convert, isn't decided yet, nor is `Bool` (chapter 12).

## 2.1a Floats, decimals and rationals

- `Float` is IEEE 754 binary64. NaN and infinity exist, as IEEE says. There are no float kinds; stable floats, the same
  bits on every machine, may come later as `f64.stable` (D82).
- `Decimal` is built in: IEEE 754 decimal128, with 34 significant digits, so `0.1 + 0.2` is exactly `0.3` (D82, D83).
- `Rational` is built in: an exact fraction of arbitrary-size integers, so it never overflows (D82, D83).

A number literal that the type it lands in can't hold exactly is written with `~` in front, and one it can hold exactly
is written without; the compiler checks both ways (D84). `~` covers literals only, not calculations that round.

```
let $a: Float = 0.5          // exact in binary
let $b: Float = ~0.1         // inexact, so it says so
let $c: Float = 0.1          // refused, fix: `~0.1`
let $d: Float = ~0.5         // refused: 0.5 is exact
let $e: Decimal = 0.1        // exact in decimal
let $f: Rational = 0.1       // exact as 1/10
```

A `Decimal` literal with more than its 34 digits needs `~` too. `Int` literals never need it; one that doesn't fit is a
`CompileTimeError`. A negative is written `~-0.1`.

## 2.2 Strings

A string is written in double quotes. Inside a string, `$` is just a character, so `"Price: $5"` needs no escape (D20).
Strings are joined by writing them side by side (chapter 4). `String.utf8` is the spelled-out form of `String` (D64).

## 2.3 Lists and maps

Lists and maps are written with `[ ]`, and the declared type decides what a literal is (D64). A map writes
`key => value`. `[]` is empty for both.

```
let $xs: List<Int> = [1, 2, 3]
let $ages: Map<String, Int> = ["Ann" => 30, "Bob" => 25]
let $none: List<Int> = []
let $nobody: Map<String, Int> = []
```

Maps come in kinds, as narrowings (D64):

| Type | Order when looping |
|---|---|
| `Map.hash` | no order to rely on |
| `Map.sorted` | sorted by key |
| `Map.insertion` | the order items were added |

A bare `Map` is `Map.insertion`. There are no tuples, since a struct names its fields, and no set literal (D64).

## 2.4 Structs

A struct is a block of fields, each written without `$` (D56). A field may have a default, written `= value` after its
type (D57). A struct is built with `[ ]` and `=`, with its fields in any order; a field without a default must be given
(D56, D57). Fields are read with `.`. Changing a field needs the whole variable to be `mut` (D43, D56).

```
struct Reading:
    celsius: Int
    place: String = "home"
end struct Reading

let mut $r: Reading = Reading[celsius = 22, place = "Bangkok"]
let $a: Reading = Reading[celsius = 22]                // place is "home"
println($r.place)
change $r.celsius = 23
```

Properties of a type are narrowings on `struct`, strongest first, and the closer repeats them (D56), as with
`struct.must_give` (chapter 8). A type's makers and methods live in its family (chapter 5).

## 2.5 Type aliases and new types

There's no bare `type` (D61):

- `type.alias` is the same type under another name, fully interchangeable.
- `type.new` is a distinct type over the same data, which doesn't mix with others. Crossing in either direction uses
  `as`, which can't fail. A literal takes the type of where it lands.

```
type.alias Numbers = List<Int>
type.new UserId = Int
type.new OrderId = Int

let $u: UserId = 5
let $o: OrderId = 7
let $n: Int = $u as Int
if $u == $o:                            // refused: UserId and OrderId don't mix

fam.type.new Ids:
    type User = Int
    type Order = Int
end fam.type.new Ids                    // Ids.User, Ids.Order
```

## 2.6 Units (after v1)

Units are designed now and built after v1 (D58). They are opt-in: a plain `Int` is just a number, and a unit applies
only where a type asks for one with `unit:`. Values then write their unit after the number, naming its family.

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

- Mixing units, or leaving one off where it's needed, is refused.
- Converting within a family uses `as`. An integer going to a bigger unit says how it rounds: `as.trunc`, `as.floor`,
  or `as.exact`, which fails if anything would be lost.
- Combined units are declared once with `per` and `x`. The compiler tracks every value as powers of its base units,
  and storing needs a declared unit whose powers match.
- Scales with an offset, such as temperature, separate points from spans: a point plus a span is a point, a point minus
  a point is a span, and a point plus a point is refused.
- Prefixes are declared once and opted into, so `kilo` on `length.meters` gives `length.kilometers`.
- `std` ships `time`, `storage` and `angle`; `sin` asks for radians.
- There's no built-in `items` unit: lengths and positions are plain `Int` (D17, D58).
