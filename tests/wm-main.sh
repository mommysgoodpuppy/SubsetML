#!/bin/sh
# Reading Workman, the build runs the entry's `main`, as Workman's runner does: here `main`
# divides by zero, so the program must fail. An entry without `main` gets no runner.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-main-') as directory:
 root = Path(directory)
 def build(name, source):
  out = root / name; out.mkdir()
  entry = root / (name + '.wm'); entry.write_text(source)
  subprocess.run([compiler, 'sml-entry', out, entry], check=True)
  executable = root / (name + '.run')
  subprocess.run(['mlton', '-output', executable, out / 'project.mlb'], check=True)
  return out, executable
 out, run = build('entry', 'let zero = 0;\nlet main = () => { let q = Int32.div(1, zero); void };\n')
 assert 'val _ = Entry.main ()' in (out / 'project_main.sml').read_text()
 assert subprocess.run([run], capture_output=True).returncode != 0
 out, run = build('library', 'let main2 = () => { Int32.div(1, 0) };\n')
 assert not (out / 'project_main.sml').exists()
 assert subprocess.run([run]).returncode == 0
PY
