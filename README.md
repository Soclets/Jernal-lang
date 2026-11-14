# Jernal

Straight to the fucking point.

The language is described in [`standard/`](standard/), and every decision behind it is in [`DECISIONS.md`](DECISIONS.md).

## Cool features

- **Families.** One name, many kinds. `fam.fn show` holds `show`, its narrowings like `show.stored` and `show.hex`,
  and versions like `area(3)` and `area(3, 4)`. A family can also be a toolbox (`geometry.area(3, 4)`) or a type's
  methods (`$r.warm_up(by: 2)`).
- **Checked units.** Planned, not designed yet.

## Cons

- The performance would likely be around Go, probably worse.
- It's a little bit more low-level than languages like Python or Ruby.
- With unique features, you'll have to learn more.

## Hello, World!

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
