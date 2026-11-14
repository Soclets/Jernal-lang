# 13. The standard package

`std` is one package, organized by path (D107). Code writes short names (D59). This chapter says exactly what each part
does, since JernOrac builds std from it alone (D127). Anything not listed here gives `NotDesignedYet`.

`need std <date>` in the manifest means std as specified on that date (D128). The build mode picks the implementation:
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

### `length`

```
$xs.length() -> Int                  // a List: the number of items
$m.length() -> Int                   // a Map: the number of entries
$s.length() -> Int                   // a String: its grapheme clusters, the same as length.graphemes()
$s.length.bytes() -> Int             // a String: its UTF-8 bytes
$s.length.code_points() -> Int       // a String: its Unicode code points
$s.length.graphemes() -> Int         // a String: its grapheme clusters
```

A string's bare `length()` counts graphemes, what a person sees as characters (D131); the narrowings give bytes, which
is also fast, and code points (D130). For `"héllo👋🏽"`, bytes, code points and graphemes are 12, 7 and 6. Which code
points form one grapheme follows the Unicode version that the `need std <date>` fixes; which version each date means
isn't decided yet.

### `List.sum`

```
$xs.sum()
```

The exact sum of a list of numbers (D38, D40): exact for integers, `Decimal` and `Rational`, and for floats the true sum
rounded once at the end, like Python's `math.fsum`. An empty list sums to `0`, and the result has the items' type.
