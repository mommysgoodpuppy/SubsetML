#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/native" "$tmp/reject"
bin/subsetml check tests/accept/integer_basics.sml
bin/subsetml native "$tmp/native" tests/accept/integer_basics.sml
cat > "$tmp/assert.sml" <<'SML'
open IntegerBasics
fun check true = () | check false = raise Fail "integer assertion"
fun overflow f = (ignore (f ()); false) handle Overflow => true
fun zeroDiv f = (ignore (f ()); false) handle Div => true
val _ = check (lo = ~2147483648 andalso hi = 2147483647 andalso hexadecimal = lo)
val _ = check (add (hi, 0) = hi andalso add (lo, hi) = ~1)
val _ = check (overflow (fn () => add (hi, 1)) andalso overflow (fn () => add (lo, ~1)))
val _ = check (overflow (fn () => subtract (lo, 1)))
val _ = check (multiply (46340, 46340) = 2147395600)
val _ = check (overflow (fn () => multiply (46341, 46341)))
val _ = check (overflow (fn () => multiply (lo, ~1)))
val _ = check (negate hi = ~2147483647 andalso absolute (~5) = 5)
val _ = check (overflow (fn () => negate lo) andalso overflow (fn () => absolute lo))
val _ = check (divide (~7, 3) = ~3 andalso divide (7, ~3) = ~3 andalso divide (~7, ~3) = 2)
val _ = check (modulo (~7, 3) = 2 andalso modulo (7, ~3) = ~2)
val _ = check (overflow (fn () => divide (lo, ~1)) andalso modulo (lo, ~1) = 0)
val _ = check (zeroDiv (fn () => divide (1, 0)) andalso zeroDiv (fn () => modulo (1, 0)))
val _ = check (defaulted (hi, 0) = hi andalso overflow (fn () => defaulted (hi, 1)))
val _ = check (ordering (lo, hi) andalso equal (hi, hi))
val _ = check (Real.== (realAdd (1.5, 2.25), 3.75))
val _ = check (text = "2147483647" andalso parsed = SOME hi)
val _ = check (precision = SOME 32 andalso maximum = SOME hi andalso minimum = SOME lo)
val _ = check (classify lo = "minimum" andalso classify 0 = "zero")
val _ = check (case count of Count n => n = hi)
val _ = check (shadow = 6 andalso shadowType = "text")
val _ = check (sum (60000, 0) = 1800030000)
val _ = print "SubsetML native signed int32: OK\n"
SML
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n' "$tmp/native/integer_basics.sml" "$tmp/assert.sml" > "$tmp/run.mlb"
# The emitted integer operations must retain 32-bit overflow even when the
# host default is 64-bit. This also catches accidentally unlowered defaults.
for width in int32 int64; do
  mlton -default-type "$width" -output "$tmp/run" "$tmp/run.mlb"
  "$tmp/run"
done
python3 - "$tmp" <<'PY'
from pathlib import Path
import subprocess, sys
root = Path(sys.argv[1])
bad = ['2147483648', '~2147483649', '0x80000000', '~0x80000001', '9' * 10000]
for index, literal in enumerate(bad):
    source = root / 'bad.sml'
    source.write_text('val x = ' + literal + '\n')
    result = subprocess.run(['bin/subsetml', 'native', root / 'reject', source], capture_output=True)
    assert result.returncode and b'outside signed 32-bit range' in result.stdout + result.stderr
    assert not list((root / 'reject').iterdir())
for text in ['val x = 1 + 1.0', 'val x = 1 / 2', 'val x = 1.0 div 2.0']:
    source.write_text(text + '\n')
    assert subprocess.run(['bin/subsetml', 'check', source], capture_output=True).returncode
# Formatting preserves authored SML rather than applying native lowering.
source.write_text('val n : int = 42\n')
result = subprocess.run(['bin/subsetml', 'fmt', source], capture_output=True, check=True)
assert b'Int32' not in result.stdout and b'int' in result.stdout
# Preserve native type identity across files, source shadowing, and hygiene.
a = root / 'a.sml'; b = root / 'b.sml'
a.write_text('structure Int32 = struct val marker = "source" end\ntype int = string\n')
b.write_text('val text : int = "kept"\nval sum = fn (a,b) => a + b\nval large = 2147483647\nval rendered = Int.toString large\n')
subprocess.run(['bin/subsetml', 'native', root / 'native', a, b], check=True)
assertion = root / 'multi.sml'
assertion.write_text('val _ = if Int32.marker = "source" andalso text = "kept" andalso sum (large, 0) = large andalso rendered = "2147483647" andalso ((sum (large, 1); false) handle Overflow => true) then () else raise Fail "multi-file integer"\n')
mlb = root / 'multi.mlb'
mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(str(p) for p in [root / 'native/a.sml', root / 'native/b.sml', assertion]) + '\n')
subprocess.run(['mlton', '-default-type', 'int64', '-output', root / 'multi', mlb], check=True)
subprocess.run([root / 'multi'], check=True)
source.write_text('val good = 42\n')
b.write_text('val bad = 2147483648\n')
assert subprocess.run(['bin/subsetml', 'native', root / 'reject', source, b], capture_output=True).returncode
assert not list((root / 'reject').iterdir())
for directory in ['one', 'two']:
    (root / directory).mkdir()
    (root / directory / 'same.sml').write_text('val x = 1\n')
result = subprocess.run(['bin/subsetml', 'native', root / 'reject', root / 'one/same.sml', root / 'two/same.sml'], capture_output=True)
assert result.returncode and b'duplicate native output' in result.stderr
assert not list((root / 'reject').iterdir())
print('Int32 bounds, type separation, native scopes and output validation: OK')
PY
