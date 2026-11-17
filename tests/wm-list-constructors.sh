#!/bin/sh
# Reading Workman, `Nil` and `Cons` are the built-in list's constructors (Workman forbids
# redeclaring them), so they read as SML's `nil` and `::` in expressions and patterns.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-list-constructors-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 entry = root / 'entry.wm'
 entry.write_text('''let xs = Cons(1, Cons(2, Nil));
let sum = match(xs) { Cons(a, Cons(b, Nil)) => { a + b }, _ => { 0 } };
let good = sum == 3 && match([3]) { [x] => { x == 3 }, _ => { false } };
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 driver = root / 'driver.sml'
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text(f'"{out / "project.mlb"}"\n"{driver}"\n')
 executable = root / 'run'
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 assert subprocess.run([executable]).returncode == 0
PY
