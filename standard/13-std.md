# 13. The standard package

`std` is one package, organized by path (D107). Code writes short names (D59). This chapter says exactly what each part
does, since JernOrac builds std from it alone (D127). Anything not listed here gives `NotDesignedYet`.

`need std <date>` in the manifest means std as specified on that date (D128). This chapter, as of now, is
`need std 2026y-11m-14d` (D137). The build mode picks the implementation:
JernOrac's built-in std under `--Interp`, JernComp's under the compiled modes. A date one of them doesn't implement gives
`NotBuiltYet` in that one. Without a `need std` line, std's names aren't visible (D59).

## 13.1 `std::io::stdio`

### `println`

```
fn println[$text: String]
```

Writes `$text` to standard output, then ends the line (D20, D21, D95). It has no formatting options (D118). A value
that isn't a `String` is converted first with `as String` (D21).

```
println("Hello, World!")
println("Age: " $age as String)
```

### Reading standard input

```
fn read_line[] -> String fails [end_of_input, not_text]
fn read_all[] -> String fails [not_text]
fn lines[] -> <a sequence of String>
```

Standard input is whatever the program is connected to: the keyboard, another program's output, or a file (D133).

- `read_line()` reads the next line, without its ending (`\n` or `\r\n`). It fails with `end_of_input` when nothing is
  left, and with `not_text` when the line isn't valid UTF-8. An empty line is `""`.
- `read_all()` reads everything left; reaching the end isn't a failure, and empty input is `""`.
- `lines()` goes through the remaining lines in a `for` loop, stopping at the end of input; a line that isn't valid
  text is a `not_text` failure.
- Each has a `.raw()` narrowing that gives bytes and never fails with `not_text`.

```
let $name: String = read_line() ?? "stranger"
for $line in lines():
    println($line)
end for
```

## 13.2 `std::env`

### `args`

```
fn args[] -> List<String> fails [not_text]
```

Gives the program's command-line arguments, without the program's own name, in order: `$args[pos: 1]` is the first
(D108). The arguments are what came after `--` on `jern`'s command line (D121). If one isn't valid text, it fails. The failure's name, `not_text`, is a placeholder.

### `args.raw`

```
args.raw() -> List<List<u8>>
```

A narrowing of `args` (D44) giving every argument as raw bytes, which never fails (D108). The exact result type,
`List<List<u8>>`, is a placeholder.

### `program_path`

```
fn program_path[] -> String
```

Gives the path of the running program (D108).

### `exit`

```
fn exit[$code: Int]
```

Ends the program with `$code` as its exit code (D11). Codes 1 to 117 are the program's; 118 to 122 belong to Jernal's
own errors (7.6), and `exit` refuses them.

## 13.3 Methods on built-in types

Methods always take `( )` (D15, D40).

### `len`

```
$xs.len() -> Int                  // a List: the number of items
$m.len() -> Int                   // a Map: the number of entries
$s.len() -> Int                   // a String: its grapheme clusters, the same as len.graphemes()
$s.len.bytes() -> Int             // a String: its UTF-8 bytes
$s.len.code_points() -> Int       // a String: its Unicode code points
$s.len.graphemes() -> Int         // a String: its grapheme clusters
```

A string's bare `len()` counts graphemes, what a person sees as characters (D131); the narrowings give bytes, which
is also fast, and code points (D130). For `"héllo👋🏽"`, bytes, code points and graphemes are 14, 7 and 6. Which code
points form one grapheme follows the Unicode version that the `need std <date>` fixes; which version each date means
isn't decided yet.

### `List.sum`

```
$xs.sum()
```

The exact sum of a list of numbers (D38, D40): exact for integers, `Decimal` and `Rational`, and for floats the true sum
rounded once at the end, like Python's `math.fsum`. An empty list sums to `0`, and the result has the items' type.

### List and Array operations

Methods that change a list need it to be `let mut`, and positions say how they count (D136):

```
$xs.add(<item>)                       // onto the end
$xs.add(<item>, <pos or offset>: <n>) // at that place, shifting the rest
$xs.remove(<pos or offset>: <n>) -> <item type>   // removes the item there and gives it back
$xs.clear()
$xs.contains(<item>) -> Bool
$xs.first() -> <item type>
$xs.last() -> <item type>
```

A position outside the list is a check, and so are `first()` and `last()` on an empty list. Adding past `len.max` or
removing below `len.min` is a check (D135). An `Array` has `contains`, `first`, `last`, `len()` and indexing, but nothing
that changes its length.

### Map operations

A map is read and changed by key, labelled like indexing (D138):

```
$m[key: <key>] -> <value type>             // a missing key is a check
$m.get(key: <key>) -> <value type>         // fails instead of a check
$m.contains(key: <key>) -> Bool
change $m[key: <key>] = <value>            // adds or replaces
$m.remove(key: <key>) -> <value type>
$m.len() -> Int
$m.keys.sorted() -> List<<key type>>
```

Looping over a `Map.hash` is a `CompileTimeError`, since it has no order to rely on; loop over `.keys.sorted()`, or use
`Map.insertion` or `Map.sorted` (D138).

### Comparing strings

`<`, `>`, `at_least` and `at_most` compare strings by Unicode code point (D138).
