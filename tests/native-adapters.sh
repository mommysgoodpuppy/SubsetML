#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-native-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 (root / 'a').mkdir(); (root / 'b').mkdir()
 (root / 'result.wm').write_text('type Result = | Ok<Number>;\nlet _ = print("R");\n')
 (root / 'a/host.wm').write_text('let value = 99;\n')
 checker = root / 'b/host.wm'
 checker.write_text('from "../result.wm" import * as ExpectedResult;\nlet value = ExpectedResult.Ok(0);\n')
 alias = root / 'checker.wm'; alias.symlink_to('b/host.wm')
 native = root / 'native adapter.sml'
 native.write_text('structure FixedHost = struct\nval _ = print "N"\nval value = ExpectedResult.Ok 7.0\nend\n')
 entry = root / 'entry.wm'
 entry.write_text('''from "./a/host.wm" import * as Decoy;
from "./b/host.wm" import * as Actual;
from "./result.wm" import * as Result;
let good = match(Actual.value) { Result.Ok(n) => {n == 7 && Decoy.value == 99} };
''')
 options = ['--native-adapter', alias, native, 'FixedHost']
 subprocess.run([compiler, 'sml-entry', out, *options, entry], cwd='/', check=True)
 # Checker output remains generated and intact; native selection occurs in the MLB scope.
 assert 'FixedHost' not in (out / 'hostModule.sml').read_text()
 assert 'structure HostModule' in (out / 'hostModule.sml').read_text()
 driver = root / 'driver.sml'; driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text('"' + str(out / 'project.mlb') + '"\n"' + str(driver) + '"\n')
 subprocess.run(['mlton', '-output', root / 'run', mlb], check=True)
 result = subprocess.run([root / 'run'], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'RN'), result
 driver.write_text('val leak = FixedHost.value\n')
 result = subprocess.run(['mlton', '-output', root / 'bad', mlb], capture_output=True)
 assert result.returncode != 0 and b'Undefined structure: FixedHost' in result.stderr, result
 # Source aliases can cross the dependencies' backend names without capturing each other.
 (root / 'one.wm').write_text('let value = 3;\n')
 (root / 'two.wm').write_text('let value = 4;\n')
 checker.write_text('from "../one.wm" import * as Two;\nfrom "../two.wm" import * as One;\nlet value = Two.value + One.value;\n')
 native.write_text('structure FixedHost = struct val value = Two.value + One.value end\n')
 entry.write_text('from "./b/host.wm" import * as Host;\nlet good = Host.value == 7;\n')
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run([compiler, 'sml-entry', out, *options, entry], check=True)
 subprocess.run(['mlton', '-output', root / 'crossed', mlb], check=True)
 subprocess.run([root / 'crossed'], check=True)
 rejected = root / 'rejected'; rejected.mkdir()
 unused = root / 'unused.wm'; unused.write_text('let x = 0;\n')
 for args, message in [
  (['--native-adapter', unused, native, 'FixedHost'], b'not in the entry graph'),
  (options + ['--native-adapter', checker, native, 'FixedHost'], b'duplicate native adapter'),
  (['--native-adapter', checker, native, '+'], b'SML structure identifier'),
  (['--native-adapter', checker, native, 'structure'], b'SML structure identifier'),
  (['--native-adapter', checker, root / 'missing.sml', 'FixedHost'], b'error'),
 ]:
  result = subprocess.run([compiler, 'sml-entry', rejected, *args, entry], capture_output=True)
  assert result.returncode != 0 and message in result.stdout + result.stderr, result
  assert not list(rejected.iterdir())
print('Native adapter selection: canonical identities, dependency aliases, scopes and diagnostics passed')
PY
