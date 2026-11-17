#!/bin/sh
# Records read as Workman reads them: a named import of a module's same-named record keeps the
# module's other names reachable, and a record literal takes the field types of the one declared
# record type with exactly its fields.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-named-records-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 # rng.wm is the structure Rng, and its record constructor is the value Rng: importing both
 # `Rng` and `next` by name must not read the projection `Rng.next` as a field of the value.
 (root / 'rng.wm').write_text('''record Rng = { seed: Real64 };
let next = (r: Rng) => { .{ seed = r.seed * 2 } };
''')
 (root / 'vec.wm').write_text('record Vec2 = { x: Real64, y: Real64 };\n')
 entry = root / 'entry.wm'
 entry.write_text('''from "./rng.wm" import { Rng, next };
from "./vec.wm" import { Vec2 };
let doubled = next(Rng(1.5));
let sun = .{ x = 480, y = 270 };
let shifted = (v: Vec2) => { .{ x = v.x + 0.5, y = v.y } };
let good = doubled.seed == 3.0 && shifted(sun).x == 480.5 && sun.y == 270.0;
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 assert 'x = 480.0' in (out / 'entry.sml').read_text()
 driver = root / 'driver.sml'
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text(f'"{out / "project.mlb"}"\n"{driver}"\n')
 executable = root / 'run'
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 assert subprocess.run([executable]).returncode == 0
PY
