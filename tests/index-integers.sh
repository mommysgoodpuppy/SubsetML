#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 scripts/stage-sml-compiler.py mlton "$tmp/compiler"
python3 - "$tmp" <<'PY'
from pathlib import Path
import random, sys
root = Path(sys.argv[1])
checks = ['''fun check true = () | check false = raise Fail "integer Basis assertion"
val _ = check (SubsetList.length [true, false] = 2)
val _ = check (case SubsetList.at ([true], ~1) of SubsetResult.Err SubsetList.InvalidIndex => true | _ => false)
val _ = check (case SubsetList.tabulate (~1, fn i => i) of SubsetResult.Err SubsetList.InvalidCount => true | _ => false)
val _ = check (case SubsetNatural.divide (1, 0) of SubsetResult.Err SubsetNatural.InvalidDivisor => true | _ => false)
val _ = check (case SubsetSource.fromNative "abc" of SubsetResult.Ok source =>
  (case SubsetSource.slice (source, 1, 2147483647) of SubsetResult.Err SubsetBytes.InvalidIndex => true | _ => false) | _ => false)
val _ = check (case SubsetUtf16Source.fromUnits [65, 55296] of SubsetResult.Ok source =>
  (case SubsetUtf16Source.slice (source, 1, 2147483647) of SubsetResult.Err SubsetUtf16Source.InvalidIndex => true | _ => false) | _ => false)
val _ = check (Elab.int32Literal "~2147483648" andalso Elab.int32Literal "~0x80000000" andalso not (Elab.int32Literal "2147483648") andalso not (Elab.int32Literal "~2147483649"))
''']
rng = random.Random(320017)
keys = [0, 1, 2, 1073741823, 1073741824, 2147483646, 2147483647] + [rng.randrange(2147483648) for _ in range(100)]
checks.append('val keys = [' + ','.join(map(str, keys)) + ']\n')
checks.append('''val original = SubsetList.foldLeft (keys, IntMap.empty, fn (key, tree) => IntMap.insert (tree, key, key))
val changed = IntMap.insert (original, 2147483647, 7)
val _ = check (SubsetList.all (keys, fn key => IntMap.find (original, key) = SOME key))
val _ = check (IntMap.find (changed, 2147483647) = SOME 7 andalso IntMap.find (original, 2147483647) = SOME 2147483647)
''')
for n in keys:
    checks.append(f'val _ = check (SubsetNatural.toString {n} = SubsetResult.Ok "{n}")\n')
    divisor = rng.randrange(1, 2147483648)
    checks.append(f'val _ = check (SubsetNatural.divide ({n},{divisor}) = SubsetResult.Ok ({n//divisor},{n%divisor}))\n')
def chars(data): return '[' + ','.join('#"\\%03d"' % b for b in data) + ']'
checks.append('val bytes = ' + chars(bytes(range(256))) + '\n')
checks.append('val _ = check (SubsetString.fromNative (Byte.bytesToString (Word8Vector.tabulate (256, Word8.fromInt))) = SubsetResult.Ok bytes)\n')
for n in [0,127,128,255,2047,2048,55295,57344,65535,65536,128512,1114111]:
    checks.append(f'val _ = check (SubsetUtf8.encode [{n}] = SubsetResult.Ok {chars(chr(n).encode("utf8"))})\n')
    checks.append(f'val _ = check (SubsetUtf8.decode {chars(chr(n).encode("utf8"))} = SubsetResult.Ok [{n}])\n')
checks.append('val _ = print "integer compiler/Basis: full-range maps, arithmetic, byte extraction, Unicode and bounds OK\\n"\n')
(root/'assert.sml').write_text(''.join(checks))
project = (root/'compiler/project.mlb').read_text().replace('"main.sml"\n', '')
(root/'compiler/test.mlb').write_text(project + '"../assert.sml"\n')
PY
if ! mlton -output "$tmp/run" "$tmp/compiler/test.mlb" > "$tmp/build.log" 2>&1; then
  cat "$tmp/build.log"
  exit 1
fi
"$tmp/run"
