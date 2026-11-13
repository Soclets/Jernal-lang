# Jernal — design decisions

Tankun decides; Jernal Design Claude proposes and records. Each entry says what was chosen and whose idea it was.
Numbers are permanent, so a decision is never renumbered. A changed decision gets a new entry that says which one it
replaces.

## Decided

**D1. Session rules, printed by a hook.** `RULES.md` holds the rules for every Jernal session, and a `SessionStart` hook
in `.claude/settings.json` prints it at startup, resume, clear and after compaction. The setup and most rules come from
Cyborg's, as its design session described them on 2026-11-13. Claude drafted the rules and the owner shaped them: the
commit, implementation and cores rules were added at the owner's request ("Where's the commit rule, impl rule, and core
count rule?"); owner quotes in commits are exact ("owner quotes shouldn't be inexact, they should be exact. If too long,
in commit say `(owner: too long)`"); the language-independent rules from Cyborg were all added ("all of the first
group"); and the result was adopted ("yea"). (Owner, 2026-11-13)
