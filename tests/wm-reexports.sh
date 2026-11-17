#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-reexports-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 (root / 'base.wm').write_text('''type Shape = | Circle<Int32.Int> | Square<Int32.Int>;
type Maybe<a> = | Missing | Present<a>;
type Token = | Token<Int32.Int>;
type Items<t> = List<t>;
record Pair<t> = { first: t, second: t };
let identity = (x) => { x };
let make = (n: Int32.Int) => { Circle(n) };
let hidden = 99;
let _ = print("B");
''')
 (root / 'facade.wm').write_text('''from "./base.wm" import { hidden as privateValue };
export from "./base.wm" import { Shape as Figure, Circle as Ring, Square as Block, Maybe, Missing as Nothing, Present as Some, Token as Ticket, Items, Pair as Duo, identity, make, };
''')
 (root / 'forward.wm').write_text('''export from "./facade.wm" import { Figure, Ring as Loop, Block, Maybe, Nothing, Some, Ticket, Items, Duo, identity as id, make };
''')
 entry = root / 'entry.wm'
 entry.write_text('''from "./forward.wm" import * as F;
let shape: F.Figure = F.make(3);
let items: F.Items<Int32.Int> = [F.id(1), F.id(2)];
let pair: F.Duo<Int32.Int> = F.Duo { first = 4, second = 5 };
let updated = F.Duo { ..pair, second = 6 };
let read = (value: F.Figure) => { match(value) { F.Loop(n) => { n }, F.Block(n) => { n } } };
let missing: F.Maybe<Int32.Int> = F.Nothing;
let present: F.Maybe<Int32.Int> = F.Some(9);
let ticket: F.Ticket = F.Ticket(10);
let good = read(shape) + pair.first + pair.second == 12 && F.id("ok") == "ok"
  && read(F.Loop(7)) == 7 && read(F.Block(8)) == 8 && updated.second == 6
  && match(missing) { F.Nothing => { true }, _ => { false } }
  && match(present) { F.Some(n) => { n == 9 }, _ => { false } }
  && match(ticket) { F.Ticket(n) => { n == 10 } };
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 driver = root / 'driver.sml'
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 mlb = root / 'run.mlb'; mlb.write_text(f'"{out / "project.mlb"}"\n"{driver}"\n')
 executable = root / 'run'
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'B'), result
 subprocess.run([compiler, 'check', out / 'entry.sml'], check=True)
 # The emitted SML aliases round-trip as ordinary SubsetML declarations.
 subprocess.run([compiler, 'roundtrip', out / 'base.sml', out / 'facade.sml',
                 out / 'forward.sml', out / 'entry.sml'], check=True)

 # Nested namespace projections and a named constructor import keep their origins. A later
 # local constructor of the same spelling shadows the imported one only from that point on.
 (root / 'nested.wm').write_text('export from "./forward.wm" import * as API;\n')
 (root / 'selected.wm').write_text('export from "./nested.wm" import { API as Shapes };\n')
 entry.write_text('''from "./selected.wm" import { Shapes as Q };
from "./forward.wm" import { Loop as Selected };
let original = match(Selected(3)) { Selected(n) => { n == 3 } };
type Local = | Selected<String>;
let own = match(Selected("local")) { Selected(s) => { s == "local" } };
let pair = Q.Duo { first = 2, second = 3 };
let updated = Q.Duo { ..pair, first = 4 };
let good = original && own && updated.first == 4 && updated.second == 3
  && match(Q.Loop(4)) { Q.Loop(n) => { n == 4 }, _ => { false } };
''')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'B'), result

 # An empty selective export still imports its dependency for initialization.
 (root / 'empty.wm').write_text('export from "./base.wm" import {};\n')
 entry.write_text('from "./empty.wm" import * as Empty;\nlet good = true;\n')
 subprocess.run([compiler, 'sml-entry', out, entry], check=True)
 subprocess.run(['mlton', '-output', executable, mlb], check=True)
 result = subprocess.run([executable], capture_output=True)
 assert (result.returncode, result.stdout) == (0, b'B'), result

 for source, expected in [
   ('from "./facade.wm" import * as F;\nlet value = F.hidden;\n', b'unbound'),
   ('from "./facade.wm" import * as F;\nlet value = F.privateValue;\n', b'unbound'),
   ('from "./facade.wm" import * as F;\nlet value = F.Circle(1);\n', b'unbound'),
   ('from "./forward.wm" import * as F;\nlet value = Base.Circle(1);\n', b'not explicitly imported'),
   ('export from "./base.wm" import { missing };\n', b'unbound selected name missing'),
   ('export from "./base.wm" import { identity as x, make as x };\n', b'duplicate imported name x'),
 ]:
  entry.write_text(source)
  rejected = root / 'rejected'; rejected.mkdir(exist_ok=True)
  result = subprocess.run([compiler, 'sml-entry', rejected, entry], capture_output=True)
  assert result.returncode != 0 and expected in result.stdout + result.stderr, result
  assert not list(rejected.iterdir())
print('WM named re-exports: canonical constructors, selective values/types, privacy and initialization passed')
PY
