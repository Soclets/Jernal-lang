# Jernal

Straight to the fucking point.

The language is described in [`standard/`](standard/), and every decision behind it is in [`DECISIONS.md`](DECISIONS.md).

**Status:** JernOrac, the oracle that runs Jernal straight from the standard (`jern run --Interp`), is being built in
[`oracle/`](oracle/), with its tests in [`tests/`](tests/). JernComp, the compiler, comes after.

## Cool features

- **Families.** One name, many kinds. `fam.fn show` holds `show`, its narrowings like `show.stored` and `show.hex`,
  and versions like `area(3)` and `area(3, 4)`. A family can also be a toolbox (`geometry.area(3, 4)`) or a type's
  methods (`$r.warm_up(by: 2)`).
- **Labels.** Things say what they mean: `$xs[pos: 1]` counts from 1 and `$xs[offset: 0]` from 0,
  `range[from: 1, to: 5]` includes its end, and a map is `Map<key: String, val: Int>`.
- **Checked units.** Designed, built after v1: `3600 time.seconds` plus `5 storage.bytes` won't compile.

# Hello, World!

```
fn.main[]:
    println("Hello, World!")
end fn.main
```

## Licences

- [`LICENSE`](LICENSE): Apache-2.0 WITH LLVM-exception, for the code. Programs you compile owe nothing.
- [`LICENSE-CC-BY-4.0`](LICENSE-CC-BY-4.0): CC BY 4.0, for this repo's writing: its Markdown files, including this
  README, `DECISIONS.md` and `RULES.md`. Credit them as
  `Jernal-lang GitHub repo text: https://github.com/Soclets/Jernal-lang`, say they're under CC BY 4.0, and say whether
  you changed them.

# Notes

The performance of JernComp (the official compiler) Jernal might be around Lua, maybe even slower.
