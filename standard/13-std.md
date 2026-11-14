# 13. The standard package

`std` is one package, organized by path (D107). Code writes short names (D59). This chapter says exactly what each part
does, since JernOrac builds std from it alone (D127). Anything not listed here gives `NotDesignedYet`.

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

### `List.sum`

```
$xs.sum()
```

The exact sum of a list of numbers (D38, D40): exact for integers, `Decimal` and `Rational`, and for floats the true sum
rounded once at the end, like Python's `math.fsum`. An empty list sums to `0`, and the result has the items' type.
