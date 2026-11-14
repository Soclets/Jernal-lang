# 2. Values and types

## 2.1 Integers

`Int` is a 64-bit signed integer, `i64` (D54). It never wraps: going past its range is a check (chapter 7), except in
`FinalPerf`, where `+`, `-` and `x` wrap (D71). Sized types such as `i32` (a 32-bit signed integer) are all available
for whoever needs them (D25). Spelling out a default is always allowed: `i64` works wherever `Int` does (D64).

Integers come in any width from 1 to 8,388,607 bits, signed (`i…`) and unsigned (`u…`) (D93). A power-of-two width is
bare (`u1`, `u4`, `i8`, `i64`, `u128`, `u256`); any other width needs the `not_two_pow.` gate (`not_two_pow.u24`), and a
bare one is refused. Widths other than 8, 16, 32, 64 and 128 are slower.

## 2.1a Floats, decimals and rationals

- Floats are `f16`, `bf16`, `f32` and `f64` (D93). `Float` is `f64`, IEEE 754 binary64. NaN and infinity exist, as IEEE says. There are no float kinds; stable floats, the same
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

Operators bind the way school maths says, tightest first: calls and `.`; unary `-`; `x`, `div.…` and `mod.…`; `+` and
`-`; comparisons; then `not`, `and`, `or` (D90). `( )` groups, and where maths gives no order between two operators,
grouping with `( )` is required: `2 + 3 x 4` is 14, and `(2 + 3) x 4` is 20.

Multiplying is `x` (D89). Overflow on purpose is a narrowing of the operation's word, the same in every build mode:
`plus.wrap`, `plus.saturate`, `minus.wrap`, `minus.saturate`, `times.wrap`, `times.saturate` (D92). On `Float`,
`.wrap` is refused. Dividing is `div` (D88). On integers, it says which kind, and a bare `div` is refused:

```
7 div.trunc 2        // 3: rounds toward zero
-7 div.floor 2       // -4: rounds down
6 div.exact 2        // 3; with a remainder, it fails with `not_exact` (D139; undefined behaviour in UB++, D94)
7 div.rational 2     // 7/2, an exact Rational
7 div 2              // refused: say which
```

On `Float`, `Decimal` and `Rational`, a bare `div` keeps the same type: `7.0 div 2.0` is `3.5`. The remainder is
`mod.trunc` or `mod.floor`, matching its division (D85). There is no `/` (D87).

A float becomes text as its shortest digits that read back exactly, with `~` in front when it isn't exactly that decimal,
so the text is a valid literal for the same float; `as.stored String` gives every stored digit (D119).

```
let $a: Float = 0.5
let $b: Float = ~0.1
println($a as String)                // 0.5
println($b as String)                // ~0.1
println($b as.stored String)         // 0.1000000000000000055511151231257827021181583404541015625
```

As text, NaN is `NaN` and infinity `inf` or `-inf`; a `Decimal` gives its exact digits; a `Rational` is reduced, as
`7/2`, `-7/2`, or `4` for a whole number (D139). `as` binds tighter than unary `-`: `-$x as i32` is `-($x as i32)`.

Floats print with no exponent for now: `1e23` prints all 24 digits (D120). A float literal outside its type's range,
such as `70000.0` for an `f16`, is a `CompileTimeError` (D120).

Converting between number types uses `as` (D91):

- A conversion that always fits is a plain `as`; one that might not fit is a plain `as` with a check.
- `as.wrap` keeps the low bits, and `as.saturate` sticks at the ends.
- From `Float`, `Decimal` or `Rational` to an integer, the rounding is always said: `as.trunc`, `as.floor`, `as.ceil`,
  `as.round.even`, `as.round.away`, or `as.exact`, a failure if anything would be lost.
- Into `Float`, a value rounds to nearest.

```
let $small: i32 = $big as i32
let $capped: u8 = $big as.saturate u8
let $i: Int = $f as.round.even Int
let $exact: Int = $r as.exact Int ?? 0
```

A `Decimal` literal with more than its 34 digits needs `~` too. `Int` literals never need it; one that doesn't fit is a
`CompileTimeError`. A negative is written `~-0.1`.

## 2.1b Booleans

`Bool` is the type of `true` and `false` (D96). As text, they're `true` and `false` (D120).

## 2.2 Strings

A string is written in double quotes. Inside a string, `$` is just a character, so `"Price: $5"` needs no escape (D20).
`\` is always special: `\"` is a quote and `\\` is a backslash, and any other `\` followed by a character is refused
(D95). Plain strings hold no control characters, such as a newline or a tab, and no U+2028 or U+2029 (D139); layout
comes with the formatting tool. Several
lines means several `println`s, since `println` ends its line.
Strings are joined by writing them side by side (chapter 4). `String.utf8` is the spelled-out form of `String` (D64).

## 2.3 Lists and maps

Lists and maps are written with `[ ]`, and the declared type decides what a literal is (D64). A map writes
`key => value`. `[]` is empty for both.

```
let $xs: List<Int> = [1, 2, 3]
let $ages: Map<key: String, val: Int> = ["Ann" => 30, "Bob" => 25]
let $none: List<Int> = []
let $nobody: Map<key: String, val: Int> = []
```

A type with one type parameter writes it bare, as `List<Int>`; with two or more, each is labelled with its name, as
`Map<key: String, val: Int>` (D102, D132).

Maps come in kinds, as narrowings (D64):

| Type | Order when looping |
|---|---|
| `Map.hash` | no order to rely on |
| `Map.sorted` | sorted by key |
| `Map.insertion` | the order items were added |

A bare `Map` is `Map.insertion`. There are no tuples, since a struct names its fields, and no set literal (D64).

## 2.3a Arrays and bounds

A type's details, values about which values it allows, go in `[ ]` after the type; `< >` holds only types (D135). All
bounds are `baked`.

- `List<<item type>>` has no limit by default, and may say `[len.min: <n>]` and `[len.max: <n>]`.
- `Array<<item type>>[len: <n>]` is a fixed-size array that lives inline, inside a struct or on the stack.
- Numbers may say `[min: <n>, max: <n>]`.
- A bounded type is a type, so it can go inside `< >`.

```
let $xs: List<Int>[len.min: 1] = [5]
let $pixel: Array<u8>[len: 4] = [255, 128, 0, 255]
let $score: Int[min: 100, max: 200] = 150
let $top: List<Int[min: 0, max: 100]>[len.max: 3] = [90, 75, 100]
```

A literal that breaks a bound is a `CompileTimeError`. Otherwise a value or an item count that might break a bound is
checked: at compile time when the compiler can tell, at runtime otherwise. Arithmetic gives back the plain type, checked
where it's stored. The case test works on bounds: `if $input: Int[min: 100, max: 200]:`.

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

## 2.4a Tagged unions

A tagged union is a block of cases, one per line; a case's data goes in `[ ]` with labelled fields (D97). It's always
written `union.tagged`; a bare `union` is refused. An enum is a union whose cases carry no data. Cases are narrowings of
the type, and a value is built like a struct.

```
union.tagged Status:
    ok
    failed[code: Int]
end union.tagged Status

let mut $s: Status = Status.failed[code = 3]
```

`match` and the case test are in 4.5a.

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
