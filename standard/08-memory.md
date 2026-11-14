# 8. Memory

## 8.1 The garbage collector

Memory is managed by a garbage collector, JernGC, alone, with no reference counting (D50). Passing references around
costs nothing, and cycles need no special handling.

- It finds pointers with stack maps, from LLVM's `gc.statepoint` and `gc.relocate`, so nothing is guessed and nothing is
  tracked while running (D66).
- It's generational: new objects are allocated by bumping a pointer in a small copying nursery; survivors move to an old
  area collected by mark-and-sweep (D67). Write barriers catch an old object getting a pointer to a new one; frozen
  values never trigger one.
- It's fully concurrent: both generations are collected alongside the running program, with read barriers as well as
  write barriers, so there are no long pauses (D68).
- `Working` mode has a torture option that collects on every allocation, so collections and timing windows happen even
  in small tests (D73).

Garbage collection can't be seen in a Jernal program: there are no finalizers (D73).

## 8.2 `give` and `copy`

`give` proves a value has a single owner, and `copy` copies right away, deeply, sharing only frozen parts; see 3.6
(D50, D52). A compiler may make `copy` lazy only where it can prove nobody could notice.

## 8.3 `must_give`

A type marked `struct.must_give` has to be given away with `give` exactly once on every path, or the program doesn't
compile (D51, D56). It's for things that have to be closed or released, such as files, connections and locks: the GC
handles memory, and `must_give` makes sure nobody forgets to close. Every way out of a function counts, including
`return early`, `?` and a failure. A value with a `must_give` part can't be copied (D52).

```
let $f: File = open($path)?
println($f.read_line())
close(give $f)                 // leaving this out is a CompileTimeError
```

## 8.4 Not freestanding

Every Jernal program runs with its runtime, including JernGC, on an operating system (D79).
