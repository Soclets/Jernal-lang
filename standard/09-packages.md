# 9. Packages and names

## 9.1 The manifest

Every program has a manifest, `Journey.siml`, even Hello World; Journey is the package manager (D76). Every project is
a package. A package can have a book, its library half, a quill, its compiler half, or both (chapter 11).

```
// Journey.siml
name hello
ver 2026y-11m-14d same

need std 2026y-11m-14d
need http 2026y-11m-14d

rule mut.never_changed refuse
```

- `name` and `ver`: a version is a labelled date, biggest first, plus whether it breaks anything: `breaks`, or the
  placeholder word `same`.
- `need <package> <date>`: one per package, with the version always written.
- `rule`: the compiler's and linter's rules, so configuration stays out of the code.

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

## 9.3 `use`

`use path as name` gives something a short name in that file (D60). The path is written short. One name per `use`, with
no wildcards.

- An unquoted name must match the last word of its path.
- A quoted name is the writer's free choice. The quotes appear only on the `use` line. A quoted name nothing could call,
  such as `""` or `"fn"`, is refused.
- If the part before the last dot is a function, an unquoted short name can't be the narrowing alone.

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
