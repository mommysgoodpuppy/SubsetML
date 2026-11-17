#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-scope-') as directory:
 root = Path(directory)
 basis = root / 'basis'; (basis / 'std').mkdir(parents=True)
 (basis / 'module-scope.paths').write_text('std/probe.wm\n')
 checker = root / 'effect.wm'; checker.write_text('let tick = () => { 1 };\n')
 native = root / 'effect.sml'
 native.write_text('structure Effect = struct val tick = fn () => (TextIO.print "I"; 1) end\n')
 (basis / 'std/probe.wm').write_text('''from "../../effect.wm" import * as Effect;
private let initialize = () => { Effect.tick() };
let started = initialize();
let keep = (x) => { x };
let show = (x) => { Text.of(x) };
''')
 entry = root / 'entry.wm'
 entry.write_text('let value = Probe.keep(2) + Probe.started;\n')
 out = root / 'out'; out.mkdir()
 args = [compiler, 'sml-entry', out, '--basis', basis,
         '--native-adapter-if-used', checker, native, 'Effect', entry]
 subprocess.run(args, check=True)
 emitted = (out / 'probe.sml').read_text()
 assert 'initialize' in emitted and 'started' in emitted and 'keep' in emitted, emitted
 assert 'val show' not in emitted, emitted
 driver = root / 'driver.sml'
 driver.write_text('val _ = if Entry.value = 3 then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text(f'"{out / "project.mlb"}"\n"{driver}"\n')
 executable = root / 'run'
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'I'), result

 # Explicit namespace imports win without initializing an unused default module. Relative
 # entry paths have the same canonical root as absolute ones.
 (root / 'own.wm').write_text('let keep = (x) => { x };\n')
 entry.write_text('from "./own.wm" import * as Probe;\nlet value = Probe.keep(2);\n')
 shadow = root / 'shadow'; shadow.mkdir()
 args[2] = shadow
 subprocess.run(args[:-1] + ['entry.wm'], cwd=root, check=True)
 assert not (shadow / 'probe.sml').exists()
 driver.write_text('val _ = if Entry.value = 2 then () else OS.Process.exit OS.Process.failure\n')
 mlb.write_text(f'"{shadow / "project.mlb"}"\n"{driver}"\n')
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b''), result

 # Needed display functions, re-exported library APIs, and all user functions remain checked.
 for source in ['let value = Probe.show(2);\n',
                'export from "std/probe.wm" import *;\n',
                'let unused = (x) => { Text.of(x) };\n']:
  entry.write_text(source)
  rejected = root / 'rejected'; rejected.mkdir(exist_ok=True)
  args[2] = rejected
  result = subprocess.run(args, capture_output=True)
  assert result.returncode != 0 and b'undecided' in result.stdout + result.stderr, result
  assert not list(rejected.iterdir())
print('WM scope: staged namespaces, unused library functions, preserved initialization and checked APIs passed')
PY
