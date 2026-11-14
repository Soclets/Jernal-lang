# 6. Failures

## 6.1 What a failure is

A failure is a real-world event a program can handle, such as a missing file (D53). A failed check is something else: a
bug in the program's own assumptions, which can't be handled (chapter 7).

| Failures | Example |
|---|---|
| a file not found, no permission, a full disk | `open($path)` |
| the network down, a connection lost | `connect($host)` |
| text that isn't a number | turning `"abc"` into an `Int` |
| text too long for a limit | a bounded string |

## 6.2 Declaring and raising

A function lists the failures it can raise on its opening line, after the result, and raises one with `fail`, which
leaves the function (D48). Failures are their own track, not a `Result` value, and can carry data. A named set of
failures is a family, with each member after the keyword `failure` (D49).

```
fn half[$n: Int] -> Int fails [odd, negative[got: Int]]:
    ...
    fail negative[got = $n]
end fn half

fam.failure file_failed:
    failure not_found
    failure denied
    failure disk_full[free: Int]
end fam.failure file_failed
```

## 6.3 Handling

A caller has these tools (D48, D55):

```
let $f: File = open($path)?                      // pass it up; refused unless this function lists it
let $port: Int = read_port() ?? 8080             // use this value instead
save_backup($data) ?? ignore                     // drop it on purpose
let $w: String = first_word($text) otherwise:    // every failure still possible must be covered
    case too_long:
        instead "…"
    case no_words $f:                            // $f names the failure, to read its data
        instead "(none)"
end otherwise
let $w: String = first_word($text) otherwise word_failed.use_placeholder
```

- `instead` gives the value used in place of the failed call. An arm may also `return`, `break` or `fail`.
- `?? ignore` is for a failure that doesn't matter; searching for `ignore` finds every one.
- A failure nobody handles crashes loudly, in every build mode (D48, D71). Handling is opt-in; a linter can make it
  stricter.

## 6.4 Handler families

A `fam.handler` holds named, reusable sets of arms, each after the keyword `handler` (D48, D49). `otherwise
family.handler` works as if its arms were written at the call. A handler's arms are checked at each use, against the
failures still possible there.

A handler that can `return` or `break` is marked `*` where it's used, so a jump out is always visible; leaving it off,
or putting it on a handler that can't jump, is refused. The compiler works out which handlers can jump.

```
fam.handler word_failed:
    handler use_placeholder:
        case too_long:
            instead "…"
        case no_words:
            instead "(none)"
    end handler use_placeholder

    handler bail:
        case too_long:
            return early
        case no_words:
            return early
    end handler bail
end fam.handler word_failed

let $w: String = first_word($text) otherwise word_failed.use_placeholder
let $w: String = first_word($text) otherwise word_failed.*bail
```
