"""Lists every distinct message text recorded in tests/*.err, with one test that shows it, for reviewing the
oracle's proposed wording in batches (D137). Usage, from the repository root:

    python3 -I oracle/tools/wording.py
"""
import glob, os, re

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
seen = {}
for path in sorted(glob.glob(os.path.join(root, "tests", "*.err"))):
    test = os.path.basename(path)[:-4]
    kind = None
    for line in open(path, encoding="utf-8"):
        match = re.match(r"^(CompileTimeError|RuntimeError|NotDesignedYet|NotBuiltYet|CompilerBug|warning):", line)
        if match:
            kind = match.group(1)
        label = re.match(r"^ (what|fix|why|when|because):\s+(.*)$", line)
        if label and label.group(1) in ("what", "fix", "why"):
            text = re.sub(r"`[^`]*`", "`…`", label.group(2))   # code differs between uses; the wording doesn't
            seen.setdefault((kind, label.group(1), text), test)
for (kind, label, text), test in sorted(seen.items(), key=lambda item: (item[0][0] or "", item[0][1], item[0][2])):
    print("%-17s %-5s %s   [%s]" % (kind, label + ":", text, test))
print("%d distinct texts" % len(seen))
