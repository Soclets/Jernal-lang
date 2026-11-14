# Jernal's tests

Each `.jern` file here is its own program (D122, standard 10.1a), sharing `Journey.siml`, which says `kind tests`.
Beside each test, compared byte for byte:

| File | What it holds | When it's missing |
|---|---|---|
| `<test>.out` | the expected standard output | nothing is expected |
| `<test>.err` | the expected error output: messages in standard 7.3's format | nothing is expected |
| `<test>.exit` | the expected exit code (standard 7.6) | 0 |

Tests are named after the decision they check: `d17_pos_counts_from_one.jern` checks D17.

```
jern test --Interp      # runs every test on JernOrac, the oracle
jern test --Working     # runs them compiled, once JernComp exists
```

## What every implementation must match

- The output, the error text and the exit code, byte for byte. Where JernOrac and JernComp differ, the standard decides
  which one is wrong (D69); if it's silent, the question goes to Tankun.
- The wording of each `what:`, `why:`, `fix:`, `when:` and `because:` is the oracle's proposal (D137) until Jernal Design
  Claude has reviewed it; the recording here is the reference meanwhile.

## Choices that aren't decisions yet

These are how the oracle runs tests now; each is with Jernal Design Claude to confirm.

- Standard input is empty, and there are no arguments. (A `.in` file for standard input is proposed.)
- A test that runs longer than 60 seconds is stopped and fails.
- Programs of several files can't be tests here yet (package tests in subfolders are proposed).
- The `use` block in `Journey.siml` is for `d60_use_gives_a_short_name.jern` only.
