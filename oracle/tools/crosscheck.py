"""Checks JernOrac's numbers against Python, an independent implementation of the same IEEE rules.

- Float text (D119): each of 300 random doubles is written as its exact decimal literal, and the
  oracle's text must be Python's shortest round-trip digits, with `~` when that isn't exact.
- Decimal (D83): 300 random +, -, x and div results must equal Python's decimal module in decimal128's
  context: 34 digits, ties to even, Emax 6144, Emin -6143.

Usage, from the repository root:  python3 -I oracle/tools/crosscheck.py <scratch folder>
"""
import decimal, os, random, struct, subprocess, sys

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
exe = os.path.join(root, "oracle", "_build", "default", "bin", "jernorac.exe")
scratch = sys.argv[1]

def plain(d):
    s = format(d, "f")
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s

def run(name, lines, expected):
    folder = os.path.join(scratch, name)
    os.makedirs(folder, exist_ok=True)
    open(os.path.join(folder, "Journey.siml"), "w").write(
        "name %s\nver 2026y-11m-14d not_broken\nneed std 2026y-11m-14d\n" % name)
    open(os.path.join(folder, "main.jern"), "w").write("\n".join(["fn.main[]:"] + lines + ["end fn.main"]) + "\n")
    got = subprocess.run([exe, "run"], cwd=folder, capture_output=True, text=True).stdout.splitlines()
    wrong = [(e, g) for e, g in zip(expected, got) if e != g]
    if len(got) != len(expected):
        wrong.append(("%d lines" % len(expected), "%d lines" % len(got)))
    print("%s: %d checked, %d wrong" % (name, len(expected), len(wrong)))
    for e, g in wrong[:10]:
        print("  expected %s, got %s" % (e, g))
    return not wrong

decimal.getcontext().prec = 2000
random.seed(14)
lines, expected = [], []
for i in range(300):
    if i % 3 == 0:
        f = random.uniform(-1000, 1000)
    elif i % 3 == 1:
        f = random.random() * 10 ** random.randint(-30, 30)
    else:
        f = struct.unpack("<d", struct.pack("<Q", random.getrandbits(64)))[0]
        if f != f or abs(f) == float("inf") or abs(f) > 1e60 or (f != 0 and abs(f) < 1e-60):
            f = random.uniform(-1, 1)
    exact = decimal.Decimal(f)
    literal = plain(exact)
    if "." not in literal:
        literal += ".0"
    lines += ["    let $v%d: Float = %s" % (i, literal), "    println($v%d as String)" % i]
    shortest = decimal.Decimal(repr(f))
    expected.append(plain(shortest) if shortest == exact else "~" + plain(shortest))
floats_ok = run("floats", lines, expected)

random.seed(83)
context = decimal.Context(prec=34, rounding=decimal.ROUND_HALF_EVEN, Emax=6144, Emin=-6143)
def number():
    digits = random.randint(1, 34)
    d = decimal.Decimal(random.randint(1, 10 ** digits - 1)).scaleb(-random.randint(0, 40))
    return -d if random.random() < 0.3 else d
lines, expected = [], []
for i in range(300):
    a, b = number(), number()
    op = ["+", "-", "x", "div"][i % 4]
    lines += ["    let $a%d: Decimal = %s" % (i, plain(a)), "    let $b%d: Decimal = %s" % (i, plain(b)),
              "    let $c%d: Decimal = $a%d %s $b%d" % (i, i, op, i), "    println($c%d as String)" % i]
    result = {"+": context.add, "-": context.subtract, "x": context.multiply, "div": context.divide}[op](a, b)
    text = plain(result)
    expected.append("0" if text == "-0" else text)
decimals_ok = run("decimals", lines, expected)
sys.exit(0 if floats_ok and decimals_ok else 1)
