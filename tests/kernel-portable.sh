#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python - "$tmp/natural_vectors.sml" <<'PY'
from pathlib import Path
import random, sys
rng = random.Random(91353)
values = [0, 1, 9, 10, 26, 99, 100, 999, 1000, 2**16, 2**31-2, 2**31-1]
values += [rng.randrange(2**31) for _ in range(50)]
rows = []
for index, value in enumerate(values):
    base = [1, 2, 10, 256, 2**16, 2**31-1][index % 6]
    whole, residue = divmod(value, base)
    rows.append(f'({value}, {base}, {whole}, {residue}, "{value}")')
Path(sys.argv[1]).write_text('structure NaturalVectors = struct\nval cases = [' + ',\n'.join(rows) + ''']
val checked = SubsetList.all (cases, fn (value, base, whole, residue, text) =>
  (case SubsetNatural.toString value of SubsetResult.Ok actual => actual = text | other => false)
  andalso (case SubsetNatural.divide (value, base) of
    SubsetResult.Ok pair => let val (q, r) = pair in q = whole andalso r = residue end
  | other => false))
  andalso SubsetList.all ([~1, ~2147483648], fn value =>
    case SubsetNatural.toString value of SubsetResult.Err SubsetNatural.InvalidNatural => true | other => false)
  andalso SubsetList.all ([0, ~1, ~2147483648], fn base =>
    case SubsetNatural.divide (10, base) of SubsetResult.Err SubsetNatural.InvalidDivisor => true | other => false)
end
''')
PY
modules=$(python scripts/basis-sources.py)
modules="$modules src/sml_list.sml src/sml_list_pair.sml src/sml_option.sml src/syntax.sml src/compiler_text.sml src/lexer.sml src/parser.sml src/types.sml src/int_map.sml src/unify.sml src/env.sml src/elab.sml src/basis.sml src/doc.sml src/sml_print.sml src/wm_print.sml src/wm_lexer.sml src/backend_names.sml src/wm_parse.sml src/normalize.sml src/translate.sml"
fixtures="$tmp/natural_vectors.sml tests/basis/kernel_portable.sml"
bin/subsetml check $modules $fixtures
{
  printf '$(SML_LIB)/basis/basis.mlb\n'
  for module in $modules; do
      if [ "$(basename "$module")" = subset_host.sml ]; then
        printf '%s\n' "$PWD/lib/subset_host.sml"
        continue
      fi
    if [ "$(basename "$module")" = subset_text_host.sml ]; then
      printf '%s\n' "$PWD/lib/subset_text_host.sml"
    else printf '%s/%s\n' "$PWD" "$module"; fi
  done
  printf '%s\n' "$tmp/natural_vectors.sml" "$PWD/tests/basis/kernel_portable.sml"
} > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
expected='index 0
index 1
index 2
portable compiler kernel: ok'
actual=$("$tmp/test")
[ "$actual" = "$expected" ] || { printf '%s\n' "$actual"; exit 1; }
mkdir -p "$tmp/wm"
bin/subsetml wm "$tmp/wm" $modules $fixtures
sh scripts/stage-text-host.sh "$tmp/wm"
if command -v wm >/dev/null 2>&1; then
  wm check "$tmp/wm/kernel_portable.wm"
  wm run "$tmp/wm/kernel_portable.wm" > "$tmp/output"
  [ "$(sed '/^$/d' "$tmp/output")" = "$expected" ]
fi
echo 'portable compiler kernel across targets: ok'
