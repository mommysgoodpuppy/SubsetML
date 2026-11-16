#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import tempfile, subprocess
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-entry-') as directory:
 root = Path(directory); out = root / 'out'; out.mkdir()
 (root / 'core.wm').write_text('type Thing = | Thing<Int32.Int>;\nlet _ = print("C");\nlet value = Thing(3);\n')
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
  (root / name).mkdir(); (root / name / 'shared.wm').write_text('type Thing = | Thing<Int32.Int>;\nlet value = Thing(1);\n')
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
 subprocess.run([compiler, 'wm', basis, 'src/subset_option_value.sml', 'src/subset_result_value.sml', 'src/subset_result.sml'], check=True)
 entry.write_text('from "basis/result.wm" import * as R;\nlet value = R.getOr(R.map(R.Ok(1), (x) => { x + 1 }), 0);\n')
 subprocess.run([compiler, 'sml-entry', out, '--basis', basis, entry], check=True)
 driver.write_text('val _ = if Entry.value = 2 then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run(['mlton', '-output', root / 'basis-entry', mlb], check=True)
 subprocess.run([root / 'basis-entry'], check=True)

 # As in Workman, an unimported `List.name` is the Basis module subset_list.wm. A lowercase
 # head is a record read, and an explicit import of the name wins.
 subprocess.run([compiler, 'wm', basis, 'src/subset_option_value.sml', 'src/subset_result_value.sml', 'src/subset_result.sml', 'src/subset_list.sml'], check=True)
 entry.write_text('record Source = { text: String };\n'
                  'let source: Source = .{ text = "abc" };\n'
                  'let before = (n: Int32.Int) => { n + 1 };\n'
                  'let kept = List.filter([1, 2, 3, 4], (n: Int32.Int) => { n > 2 });\n'
                  'let matched = if (source.text == "abc") { 1 } else { 0 };\n'
                  'let value = before(List.length(kept)) + List.length(List.reverse(kept)) + matched;\n')
 subprocess.run([compiler, 'sml-entry', out, '--basis', basis, entry], check=True)
 assert 'SubsetList.filter' in (out / 'entry.sml').read_text()
 driver.write_text('val _ = if Entry.value = 6 then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run(['mlton', '-output', root / 'implicit-basis', mlb], check=True)
 subprocess.run([root / 'implicit-basis'], check=True)

 # Bare Option/Result types and constructors are the source Basis datatypes. In particular,
 # an option returned by a Basis collection can be matched without an explicit open.
 subprocess.run([compiler, 'wm', basis, 'src/subset_option_value.sml', 'src/subset_result_value.sml', 'src/subset_result.sml', 'src/subset_option.sml'], check=True)
 entry.write_text('''from "basis/option_value.wm" import * as O;
from "basis/result.wm" import * as R;
let option: Option<Int32.Int> = Some(4);
let missing: Option<Int32.Int> = None;
let result: Result<Int32.Int, String> = Ok(5);
let failure: Result<Int32.Int, String> = Err("bad");
let found = List.find([1, 2, 3], (n) => { n == 2 });
let value = match(found) {
  Some(n) => { n + Option.getOr(option, 0) + R.getOr(result, 0) },
  None => { 0 }
};
let good = value == 11 && Option.isNone(missing) && R.isErr(failure)
  && match(R.toOption(Ok(7))) { Some(n) => { n == 7 }, None => { false } }
  && match(option) { O.Some(n) => { n == 4 }, O.None => { false } };
''')
 subprocess.run([compiler, 'sml-entry', out, '--basis', basis, entry], check=True)
 driver.write_text('val _ = if Entry.good then () else OS.Process.exit OS.Process.failure\n')
 subprocess.run(['mlton', '-output', root / 'basis-constructors', mlb], check=True)
 subprocess.run([root / 'basis-constructors'], check=True)
 # Implicit opens are private. They do not export the defaults through the entry module.
 user = root / 'user.wm'
 user.write_text('from "./entry.wm" import * as Entry;\nlet leaked = Entry.Some(1);\n')
 result = subprocess.run([compiler, 'sml-entry', root / 'private-defaults', '--basis', basis, user], capture_output=True)
 assert result.returncode != 0 and b'unbound' in result.stdout + result.stderr, result
 # A local datatype shadows the defaults; no textual constructor replacement is involved.
 entry.write_text('''type Option = | None | Some<String>;
type Result = | Ok<String> | Err;
let good = (match(Some("local")) { Some(s) => { s == "local" }, None => { false } })
  && match(Ok("own")) { Ok(s) => { s == "own" }, Err => { false } };
''')
 subprocess.run([compiler, 'sml-entry', out, '--basis', basis, entry], check=True)
 subprocess.run(['mlton', '-output', root / 'shadowed-constructors', mlb], check=True)
 subprocess.run([root / 'shadowed-constructors'], check=True)
 # Plain imports are private opens, but they do not privately declare the imported types.
 (root / 'types.wm').write_text('type Item = | Item<Int32.Int>;\nrecord Box = { payload: Item };\n')
 entry.write_text('''from "./types.wm" import *;
let value = Item(3);
let boxed: Box = .{ payload = value };
let good = match(boxed.payload) { Item(n) => { n == 3 } };
''')
 subprocess.run([compiler, 'sml-entry', out, '--basis', basis, entry], check=True)
 subprocess.run(['mlton', '-output', root / 'private-import-types', mlb], check=True)
 subprocess.run([root / 'private-import-types'], check=True)

 rejected = root / 'rejected'; rejected.mkdir()
 for body, expected in [
  ('from "./left.wm" import * as Left;\nlet value = Core.value;\n', b'not explicitly imported'),
  ('from "./missing.wm" import * as Missing;\n', b'cannot resolve import'),
  ('let value = 1;\nfrom "./core.wm" import * as Core;\n', b'imports must precede'),
  ('from "./core.wm" import { value;\n', b'unterminated'),
  ('from "./cycle.wm" import * as Cycle;\n', b'import cycle'),
  ('from "basis/result.wm" import * as R;\n', b'basis/ imports need --basis DIR'),
 ]:
  entry.write_text(body)
  (root / 'cycle.wm').write_text('from "./entry.wm" import * as Entry;\n')
  result = subprocess.run([compiler, 'sml-entry', rejected, entry], capture_output=True)
  assert result.returncode != 0 and expected in result.stdout + result.stderr, (body, result)
  assert not list(rejected.iterdir())
print('WM entry discovery: canonical diamond, private scope, source order, distinct modules, basis/ imports, implicit Basis namespaces and diagnostics passed')
PY
