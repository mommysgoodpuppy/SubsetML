#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-no-embedded-') as directory:
 root = Path(directory); out = root / 'sml'; out.mkdir()
 entry = root / 'entry.wm'
 entry.write_text('''record Fields = {
  open: Number,
  val: Number,
  datatype: Number,
};
let fields = Fields(1, 2, 3);
let copied = Fields { ..fields,
  open = 4,
};
let open = (x) => {x + 1};
let good = copied.open == 4 && fields.val == 2 && fields.datatype == 3 &&
  open(4) == 5;
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 driver = root / 'driver.sml'; driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text('"' + str(out / 'project.mlb') + '"\n"' + str(driver) + '"\n')
 subprocess.run(['mlton', '-output', root / 'run', mlb], check=True)
 subprocess.run([root / 'run'], check=True)
 rejected = root / 'rejected'; rejected.mkdir()
 for source in ['val x = 1.0;\n', 'datatype t = C;\n', 'open List;\n',
                'let f = () => {\nval x = 1.0;\nx\n};\n']:
  entry.write_text(source)
  result = subprocess.run([compiler, 'sml-entry', rejected, entry], capture_output=True)
  assert result.returncode != 0, (source, result)
  assert not list(rejected.iterdir())
 # Supported SML forms remain checker features; Basis opens already violate subset rule F2.
 for source, reason in [
  ("val 'a identity = fn (x : 'a) => x\n", 'explicit val type variables'),
  ('val x = 1.0 and rec f = fn n => n\n', 'mixed plain/recursive'),
  ('open List\n', 'non-project structure'),
  ('type r = {x: real} and t = real\n', 'type groups containing records'),
  ("val f = fn () => let val 'a identity = fn (x : 'a) => x in identity 1.0 end\n", 'explicit val type variables'),
 ]:
  file = root / 'unsupported.sml'; file.write_text(source)
  if reason != 'non-project structure':
   subprocess.run([compiler, 'check', file], check=True)
  result = subprocess.run([compiler, 'wm', rejected, file], capture_output=True)
  assert result.returncode != 0 and reason.encode() in result.stderr, (source, result)
  assert b'embedded SML declarations are not supported' in result.stderr
  assert not list(rejected.iterdir())
print('No embedded declarations: reserved labels work; WM input and unsupported SML output fail explicitly')
PY
