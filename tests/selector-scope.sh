#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
prefix = '''structure Probe = struct
 type position = { index : real }
 type span = { endPos : position }
 type row = { span : span }
'''
branch = 'row :: _ => let val endIndex = #index (#endPos (#span row)) in endIndex end | [] => 0.0'
accept = {
 'case': 'val read = fn (rows : row list) => case rows of ' + branch,
 'derived': 'val read = fn (rows : row list) => (fn ' + branch + ')(rows)',
 'whole_constraint': 'val read = (fn rows => case rows of ' + branch + ') : row list -> real',
 'polymorphic_local': '''val read = fn (rows : row list) => case rows of
 row :: _ => let val id = fn x => x val a = id (#index (#endPos (#span row)))
 val b = id "ok" in if b = "ok" then a else 0.0 end | [] => 0.0''',
 'captured_alias': '''val read = (fn row => let val get = fn () => #span row
 val getEnd = fn () => #endPos (get ()) val result = #index (getEnd ())
 in result end) : row -> real
 val read = fn rows => case rows of row :: _ => read row | [] => 0.0''',
}
reject = {
 'unresolved': 'val read = fn rows => case rows of ' + branch,
 'captured_monomorphic': '''val read = fn row => let val get = fn () => #span row
 val number : real = get () val text : string = get () in text end''',
 'missing_field': '''val read = fn (rows : row list) => case rows of row :: _ =>
 let val result = #missing (#endPos (#span row)) in result end | [] => 0.0''',
 'nonrecord': '''val read = fn (rows : row list) => case rows of row :: _ =>
 let val result = #bad (#index (#endPos (#span row))) in result end | [] => 0.0''',
}
with tempfile.TemporaryDirectory(prefix='subsetml-selector-scope-') as directory:
 root = Path(directory)
 for name, body in {**accept, **reject}.items():
  source = root / 'probe.sml'; source.write_text(prefix + body + '\nend\n')
  result = subprocess.run([compiler, 'check', source], capture_output=True, text=True)
  mlb = root / (name + '.mlb')
  driver = root / (name + '-run.sml')
  driver.write_text('val _ = if Real.== (Probe.read [{span = {endPos = {index = 7.0}}}], 7.0) then () else OS.Process.exit OS.Process.failure\n')
  mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + str(source) + '\n' + (str(driver) + '\n' if name in accept else ''))
  native = subprocess.run(['mlton', '-output', root / name, mlb], capture_output=True, text=True)
  expected = name in accept
  assert (result.returncode == 0) == expected, (name, result.stdout, result.stderr)
  assert (native.returncode == 0) == expected, (name, native.stdout, native.stderr)
  if expected:
   subprocess.run([root / name], check=True)
   subprocess.run([compiler, 'roundtrip', source], check=True)
print('selector scope: case/application equivalence, constraints, closure and invalid projections agree with MLton')
PY
