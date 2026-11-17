#!/bin/sh
# Reading Workman, an undecided numeric literal or operator is resolved by its structure-level
# declaration, as Workman resolves it (Appendix E allows that context): a local `let r = 235;`
# used as a real is a real, a local left undecided defaults to int, and a local function stays
# monomorphic.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-local-defaults-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 entry = root / 'entry.wm'
 entry.write_text('''let real = () => { let r = 235; let s = r + 0.5; s };
let integer = () => { let n = 3; n * 2 };
let local = () => { let double = (x) => x * 2; double(1.5) };
let good = real() == 235.5 && integer() == 6 && local() == 3.0;
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 text = (out / 'entry.sml').read_text()
 assert 'val r = 235.0' in text and 'val n = 3' in text, text
 driver = root / 'driver.sml'
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text(f'"{out / "project.mlb"}"\n"{driver}"\n')
 executable = root / 'run'
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 assert subprocess.run([executable]).returncode == 0
PY
