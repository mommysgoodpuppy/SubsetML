#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-record-facades-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 (root / 'hidden.wm').write_text('type Hidden = | Hidden<Int32.Int>;\n')
 (root / 'base.wm').write_text('''from "./hidden.wm" import * as H;
record Pair<a> = { left: a, right: a };
record Box<a> = { value: a, secret: H.Hidden };
let secret = () => { H.Hidden(7) };
let read = (box: Box<Int32.Int>) => { match(box.secret) { H.Hidden(n) => { n + box.value } } };
let _ = print("I");
''')
 (root / 'facade.wm').write_text('''export from "./base.wm" import { Pair as Duo, Box as Wrapped, secret, read };
''')
 (root / 'forward.wm').write_text('''export from "./facade.wm" import { Duo as Pair, Wrapped as Box, secret, read };
''')
 (root / 'outer.wm').write_text('export from "./forward.wm" import * as Records;\n')
 entry = root / 'entry.wm'
 header = '''from "./outer.wm" import { Records as R };
from "./forward.wm" import { Pair as LocalPair };
'''
 entry.write_text(header + '''let mark = (tag, value) => { print(tag); value };
let seed = (tag) => { print(tag); R.Pair { left = 1, right = 2 } };
let point = R.Pair { left = mark("A", 10), ..seed("B"), right = mark("C", 20), ..seed("D") };
let box = R.Box { value = 5, secret = R.secret() };
let changed = R.Box { ..box, value = 6 };
let text = LocalPair { left = "left", right = "right" };
let shadow = () => { type LocalPair = | LocalPair<Int32.Int>; match(LocalPair(1)) { LocalPair(n) => { n } } };
let again = LocalPair { left = 3, right = 4 };
let good = point.left == 1 && point.right == 2 && R.read(box) == 12 && R.read(changed) == 13
  && text.left == "left" && shadow() == 1 && again.left == 3;
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 subprocess.run([compiler, 'check', out / 'entry.sml'], check=True)
 driver = root / 'driver.sml'
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text(f'"{out / "project.mlb"}"\n"{driver}"\n')
 executable = root / 'run'
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'IABCD'), result

 # A local record shadows a private imported record only from its declaration onward.
 entry.write_text(header + '''let first = LocalPair { left = 1, right = 2 };
record LocalPair = { tag: Bool };
let own = LocalPair { tag = true };
let good = first.left == 1 && own.tag;
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'I'), result

 for source, expected in [
   ('let bad = R.Pair { left = 1 };', b'missing record field right'),
   ('let bad = R.Pair { left = 1, left = 2, right = 3 };', b'duplicate record field left'),
   ('let bad = R.Pair { left = 1, right = "wrong" };', b'expected'),
   ('let bad = R.Pair { left = "wrong", ..R.Pair { left = 1, right = 2 } };', b'expected'),
   ('let bad = R.Box { value = 1, secret = 2 };', b'expected'),
   ('from "./facade.wm" import * as F;\nlet bad = F.Pair { left = 1, right = 2 };', b'unknown record layout'),
   ('let bad = R.Hidden { value = 1 };', b'unknown record layout'),
   ('type LocalPair = | LocalPair<Int32.Int>;\nlet bad = LocalPair { left = 1, right = 2 };', b'unknown record layout'),
 ]:
  entry.write_text(header + source + '\n')
  rejected = root / 'rejected'; rejected.mkdir(exist_ok=True)
  result = subprocess.run([compiler, 'sml-entry', rejected, entry], capture_output=True)
  assert result.returncode != 0 and expected in result.stdout + result.stderr, result
  assert not list(rejected.iterdir())
print('record facades: forwarded layouts, generics, private fields, ordered updates and lexical shadowing passed')
PY
