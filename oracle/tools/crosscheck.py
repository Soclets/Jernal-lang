"""Checks JernOrac's numbers against Python, an independent implementation of the same IEEE rules.

- Float text (D119): each of 300 random doubles is written as its exact decimal literal, and the
  oracle's text must be Python's shortest round-trip digits, with `~` when that isn't exact.
- Decimal (D83): 300 random +, -, x and div results must equal Python's decimal module in decimal128's
  context: 34 digits, ties to even, Emax 6144, Emin -6143.
- Integers (D85, D88): div.trunc, div.floor, mod.trunc and mod.floor against Python's integers.
- Rational (D83, D139): +, -, x and div against fractions.Fraction, printed reduced.
- f32 and f16 (D93): sums rounded to the format must equal Python's struct rounding ('f' and 'e').

Usage, from the repository root:  python3 -I oracle/tools/crosscheck.py <scratch folder>
"""
import decimal, fractions, os, random, struct, subprocess, sys

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
random.seed(88)
lines, expected = [], []
for i in range(300):
    a = random.randint(-10**12, 10**12)
    b = random.randint(-10**6, 10**6) or 7
    op = ["div.trunc", "div.floor", "mod.trunc", "mod.floor"][i % 4]
    lines += ["    let $a%d: Int = %d" % (i, a), "    let $b%d: Int = %d" % (i, b),
              "    let $c%d: Int = $a%d %s $b%d" % (i, i, op, i), "    println($c%d as String)" % i]
    q = abs(a) // abs(b) * (1 if (a >= 0) == (b >= 0) else -1)   # toward zero
    expected.append(str({"div.trunc": q, "div.floor": a // b, "mod.trunc": a - q * b, "mod.floor": a % b}[op]))
integers_ok = run("integers", lines, expected)

random.seed(39)
lines, expected = [], []
for i in range(300):
    a = fractions.Fraction(random.randint(-10**9, 10**9), random.randint(1, 10**6))
    b = fractions.Fraction(random.randint(-10**9, 10**9) or 1, random.randint(1, 10**6))
    op = ["+", "-", "x", "div"][i % 4]
    lines += ["    let $a%d: Rational = %d div.rational %d" % (i, a.numerator, a.denominator),
              "    let $b%d: Rational = %d div.rational %d" % (i, b.numerator, b.denominator),
              "    let $c%d: Rational = $a%d %s $b%d" % (i, i, op, i), "    println($c%d as String)" % i]
    r = {"+": a + b, "-": a - b, "x": a * b, "div": a / b}[op]
    expected.append(str(r.numerator) if r.denominator == 1 else "%d/%d" % (r.numerator, r.denominator))
rationals_ok = run("rationals", lines, expected)

random.seed(32)
lines, expected = [], []
for i in range(300):
    kind, code = (("f32", "f") if i % 2 == 0 else ("f16", "e"))
    limit = 1e30 if kind == "f32" else 60000.0
    def value():
        x = random.uniform(-1, 1) * (limit if random.random() < 0.3 else random.choice([1.0, 100.0, 1e-3]))
        return struct.unpack("<" + code, struct.pack("<" + code, x))[0]
    a, b = value(), value()
    total = a + b
    try:
        rounded = struct.unpack("<" + code, struct.pack("<" + code, total))[0]
    except OverflowError:
        continue
    if abs(rounded) == float("inf"):
        continue
    lines += ["    let $a%d: %s = %s" % (i, kind, plain(decimal.Decimal(a)) + ("" if "." in plain(decimal.Decimal(a)) else ".0")),
              "    let $b%d: %s = %s" % (i, kind, plain(decimal.Decimal(b)) + ("" if "." in plain(decimal.Decimal(b)) else ".0")),
              "    let $c%d: %s = $a%d + $b%d" % (i, kind, i, i), "    println($c%d as.stored String)" % i]
    expected.append(plain(decimal.Decimal(rounded)))
small_floats_ok = run("small_floats", lines, expected)
sys.exit(0 if floats_ok and decimals_ok and integers_ok and rationals_ok and small_floats_ok else 1)
