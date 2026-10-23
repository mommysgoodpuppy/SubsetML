#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import tempfile, subprocess
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-entry-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 (root / 'core.wm').write_text('type Thing = | Thing<I32>;\nlet _ = print("C");\nlet value = Thing(3);\n')
 (root / 'alias.wm').symlink_to('core.wm')
 (root / 'left.wm').write_text('from "./core.wm" import * as Core;\nlet _ = print("L");\nlet value = Core.value;\n')
 (root / 'right.wm').write_text('from "./alias.wm" import * as Same;\nlet _ = print("R");\nlet value = Same.value;\n')
 entry = root / 'entry.wm'
 entry.write_text('''from "./left.wm" import * as Left;
from "./right.wm" import * as Right;
from "./core.wm" import * as Core;
let _ = print("E");
let read = (value) => { match(value) { Core.Thing(n) => {n} } };
let good = read(Left.value) + read(Right.value) == 6;
''')
 subprocess.run([compiler, 'sml-entry', out, entry], cwd='/', check=True)
 assert len(list(out.glob('*.sml'))) == 4
 subprocess.run([compiler, 'check', out / 'entry.sml'], check=True)
 driver = root / 'driver.sml'; driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'test.mlb'; mlb.write_text('"' + str(out / 'project.mlb') + '"\n"' + str(driver) + '"\n')
 subprocess.run(['mlton', '-output', root / 'run', mlb], check=True)
 result = subprocess.run([root / 'run'], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'CLRE'), result
 # An already emitted sibling still cannot leak into another module's working scope.
 right = out / 'right.sml'; original = right.read_text()
 right.write_text(original + '\nval leak = Left.value\n')
 result = subprocess.run(['mlton', '-output', root / 'bad', mlb], capture_output=True)
 assert result.returncode != 0 and b'Undefined structure: Left' in result.stderr, result
 right.write_text(original)
 # The build exposes the entry, not all its private dependency structures.
 driver.write_text('val leak = Core.value\n')
 result = subprocess.run(['mlton', '-output', root / 'bad', mlb], capture_output=True)
 assert result.returncode != 0 and b'Undefined structure: Core' in result.stderr, result
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')

 for name in ['a', 'b']:
  (root / name).mkdir(); (root / name / 'shared.wm').write_text('type Thing = | Thing<I32>;\nlet value = Thing(1);\n')
 entry.write_text('''from "./a/shared.wm" import * as A;
from "./b/shared.wm" import * as B;
let readA = (v) => { match(v) { A.Thing(n) => {n} } };
let readB = (v) => { match(v) { B.Thing(n) => {n} } };
let value = readA(A.value) + readB(B.value);
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 assert (out / 'shared.sml').exists() and (out / 'sharedModule.sml').exists()
 driver.write_text('val _ = if Entry.value = 2 then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run(['mlton', '-output', root / 'distinct', mlb], check=True)
 subprocess.run([root / 'distinct'], check=True)

 # File stems are backend hints, including punctuation, leading digits and empty hints.
 (root / 'native-lex.wm').write_text('let value = 1;\n')
 (root / 'native_lex.wm').write_text('let value = 2;\n')
 (root / '123.wm').write_text('let value = 3;\n')
 (root / '---.wm').write_text('let value = 4;\n')
 entry.write_text('from "./native-lex.wm" import * as A;\nfrom "./native_lex.wm" import * as B;\nfrom "./123.wm" import * as C;\nfrom "./---.wm" import * as D;\nlet value = A.value + B.value + C.value + D.value;\n')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 driver.write_text('val _ = if Entry.value = 10 then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run(['mlton', '-output', root / 'spelling', mlb], check=True)
 subprocess.run([root / 'spelling'], check=True)

 # "basis/x.wm" names the generated Basis module subset_x.wm in the --basis directory.
 basis = root / 'basis'; basis.mkdir()
 subprocess.run([compiler, 'wm', basis, 'src/subset_result.sml'], check=True)
 entry.write_text('from "basis/result.wm" import * as R;\nlet value = R.getOr(R.map(R.Ok(1), (x) => { x + 1 }), 0);\n')
 subprocess.run([compiler, 'sml-entry', out, '--basis', basis, entry], check=True)
 driver.write_text('val _ = if Entry.value = 2 then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run(['mlton', '-output', root / 'basis-entry', mlb], check=True)
 subprocess.run([root / 'basis-entry'], check=True)

 rejected = root / 'rejected'; rejected.mkdir()
 for body, expected in [
  ('from "./left.wm" import * as Left;\nlet value = Core.value;\n', b'not explicitly imported'),
  ('from "./missing.wm" import * as Missing;\n', b'cannot resolve import'),
  ('let value = 1;\nfrom "./core.wm" import * as Core;\n', b'imports must precede'),
  ('from "./core.wm" import { value };\n', b'header namespace imports'),
  ('from "./cycle.wm" import * as Cycle;\n', b'import cycle'),
  ('from "basis/result.wm" import * as R;\n', b'basis/ imports need --basis DIR'),
 ]:
  entry.write_text(body)
  (root / 'cycle.wm').write_text('from "./entry.wm" import * as Entry;\n')
  result = subprocess.run([compiler, 'sml-entry', rejected, entry], capture_output=True)
  assert result.returncode != 0 and expected in result.stdout + result.stderr, (body, result)
  assert not list(rejected.iterdir())
print('WM entry discovery: canonical diamond, private scope, source order, distinct modules, basis/ imports and diagnostics passed')
PY
