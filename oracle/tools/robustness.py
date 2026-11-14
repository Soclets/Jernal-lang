"""Rule 13: a bad program never crashes the oracle.

Runs JernOrac on every test program changed in small ways (cut short after each line, each line
removed, each word removed or shortened) and reports any CompilerBug (exit 118). Runs 3 at a time
(rule 11). Usage, from the repository root:

    python3 -I oracle/tools/robustness.py <scratch folder>
"""
import concurrent.futures, glob, os, shutil, subprocess, sys

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
tests = os.path.join(root, "tests")
scratch = sys.argv[1]
os.makedirs(scratch, exist_ok=True)
# its own copy, so rebuilding the oracle meanwhile can't break the run
exe = os.path.join(scratch, "jernorac.exe")
shutil.copy(os.path.join(root, "oracle", "_build", "default", "bin", "jernorac.exe"), exe)

variants = []
for path in sorted(glob.glob(tests + "/*.jern")):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    for n in range(1, len(lines)):
        variants.append((path, "\n".join(lines[:n])))
    for n in range(len(lines)):
        variants.append((path, "\n".join(lines[:n] + lines[n + 1:])))
    for i, line in enumerate(lines):
        words = line.split(" ")
        for j, w in enumerate(words):
            if w == "":
                continue
            variants.append((path, "\n".join(lines[:i] + [" ".join(words[:j] + words[j + 1:])] + lines[i + 1:])))
            if len(w) > 1:
                shorter = " ".join(words[:j] + [w[:-1]] + words[j + 1:])
                variants.append((path, "\n".join(lines[:i] + [shorter] + lines[i + 1:])))

def run(k):
    path, text = variants[k]
    work = os.path.join(scratch, "w%d" % (k % 3))
    os.makedirs(work, exist_ok=True)
    shutil.copy(os.path.join(tests, "Journey.siml"), work)
    name = "t%d.jern" % k
    open(os.path.join(work, name), "w").write(text)
    try:
        r = subprocess.run([exe, "run-test", work, name], capture_output=True, timeout=5, stdin=subprocess.DEVNULL)
        bad = r.returncode == 118 or b"CompilerBug" in r.stderr
        found = (path, text, r.stderr.decode(errors="replace")) if bad else None
    except subprocess.TimeoutExpired:
        found = None  # the program's own endless loop
    os.remove(os.path.join(work, name))
    return found

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    bugs = [b for b in pool.map(run, range(len(variants))) if b]
print("programs:", len(variants), "crashes:", len(bugs))
for path, text, error in bugs[:10]:
    print("====", path)
    print(text[:800])
    print("--", error[:400])
