# 9. Packages and names

## 9.1 The manifest

Every program has a manifest, `Journey.siml`, even Hello World; Journey is the package manager (D76). Every project is
a package. A package can have a book, its library half, a quill, its compiler half, or both (chapter 11).

```
// Journey.siml
name hello
ver 2026y-11m-14d not_broken

need std 2026y-11m-14d
need http 2026y-11m-14d

rule mut.never_changed refuse
```

- `name` and `ver`: a version is a labelled date, biggest first, plus `breaks` if it changed or removed something
  `pub.all`, or `not_broken` otherwise (D110). Journey checks the word against what changed, and a `need` moves to later
  `not_broken` releases on its own, never to a `breaks` one.
- `need <package> <date>`: one per package, with the version always written. There are no package features; an
  optional part is a separate package (D112).
- `rule`: the compiler's and linter's rules, so configuration stays out of the code.

A line that applies only in some situations starts with a scope, joined with `.`: `target.` (operating system or CPU)
or `mode.` (build mode). Scopes stack, strongest first (D111).

```
target.windows need win_console 2026y-11m-01d
mode.Working rule unused.variable warn
```

The manifest is checked, with errors in 7.3's format, and compiled into the fastest form for the tools to load,
recompiled whenever it changes (D113).

siml is one fact per line: what the line is, then its values separated by spaces. There are no sections, `=` or `;`.
Blank lines group, quotes are used only when needed, comments are `//`, and a list is repeated lines (D76).

## 9.2 Names without imports

A file has no import lines (D59). Every package the manifest lists is visible by short names, with no path. A full path
(`http::get`, `pkg::get` for the program's own package) is needed only when a short name clashes. A clash is always a
`CompileTimeError` that lists the full paths, never a quiet pick, even when one side is the program's own code.

```
fn.main[]:
    println("hi")                       // from std
    let $page: String = get($url)?      // from http: nothing else is called `get`
end fn.main
```

## 9.2a `pub`

A declaration without `pub` is seen only in its own file. `pub.pkg` shows it to its package, and `pub.all` to everyone;
a bare `pub` is refused (D106). `pub.…` goes in front of the whole declaration, and closers don't repeat it. Fields and
family members each take their own.

```
fn helper[...]:                     // this file only
pub.pkg fn parse[...]:              // the package
pub.all fn get[...]:                // everyone

pub.all struct Reading:
    pub.all celsius: Int
    place: String
end struct Reading
```

Using something that isn't visible is refused with no `fix:`, since making it visible is the other author's choice. A
`pub.…` signature that mentions a less visible type is refused. `pub.…` on `fn.main` is refused.

## 9.2b The standard package

Jernal has one standard package, `std`, organized by path (D107): `std::io` for everything that talks to the outside
world (`std::io::stdio`, `std::io::file`, `std::io::net`), `std::env` for the program's surroundings, `std::time` and
`std::math`. Code writes short names: `println` is `std::io::stdio::println`.

`args()`, in `std::env`, gives the program's arguments as a `List<String>`, without the program's own name;
`program_path()` gives its path (D108). An argument that isn't valid text is a failure of `args()`, and `args.raw()`
gives raw bytes.

## 9.3 `use`

`use path as name` gives something a short name in one file (D60). `use` lines live in `Journey.siml`, inside a block
named after the file, never in a `.jern` file (D114). An `all:` ... `end all` block applies to every file; the same
short name in `all` and a file's block is a clash, and the manifest is refused (D115). The path is written short. One name per `use`, with
no wildcards.

- An unquoted name must match the last word of its path.
- A quoted name is the writer's free choice. The quotes appear only on the `use` line. A quoted name nothing could call,
  such as `""` or `"fn"`, is refused.
- If the part before the last dot is a function, an unquoted short name can't be the narrowing alone.

```
main.jern:
use time.seconds as seconds
end main.jern
```

```
use time.seconds as seconds          // a family member
use time.seconds as "secs"           // quoted: any name
use time.seconds as minutes          // refused: it would lie
use show.stored as stored            // refused: `show` is a function
use show.stored as "show_stored"     // quoted: allowed
```

## 9.4 `my::`

A name of the program's own that is also a built-in word (a keyword, a word operator such as `and` or `at_least`, a
built-in type such as `Int`, or `main`) is written with `my::` wherever it appears: its declaration, its closer and every
use (D63). Every other name stays bare. A field is exempt, since it only appears after a `.` or in its struct's
declaration: `$point.x` needs no `my::`, though `x` multiplies (D89). If Jernal later adds a built-in word that old code used as a bare name, that code
gets a `CompileTimeError` saying to add `my::`, never a silent change of meaning.

```
fn my::main[]:
    ...
end fn my::main
my::main()
```
