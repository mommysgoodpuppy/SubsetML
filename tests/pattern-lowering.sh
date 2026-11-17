#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import tempfile, subprocess
compiler = Path('bin/subsetml').resolve()
repo = Path.cwd()
wm = repo.parents[1] if (repo.parents[1] / 'src/main.ts').is_file() else repo.parent / 'wm-mini'
with tempfile.TemporaryDirectory(prefix='subsetml-patterns-') as directory:
    root = Path(directory)
    out = root / 'sml'
    out.mkdir()
    constants = root / 'constants.wm'
    constants.write_text('let number = 2;\nlet text = "yes";\ntype Kind = | Red | Blue;\nlet kind = Red;\n')
    use = root / 'use.wm'
    use.write_text('''from "./constants.wm" import * as C;
type Wrap<T> = | Wrap<T> | Empty;
let pick = match {
  Wrap([1, C.number, x]) => { x },
  Wrap([1, 3, x]) => { x + 10 },
  _ => { 0 }
};
let x = 7;
let shadow = match {
  (Var(x), x) => { x },
  _ => { 99 }
};
let text = match { C.text => { true }, _ => { false } };
let kind = match { C.kind => { true }, C.Blue => { false }, _ => { false } };
let negative = match { =(-2.5) => { true }, _ => { false } };
let partial = match { 42 => { true } };
let upper = 5;
let keepScope = match { (Var(upper), 0) => { upper }, _ => { upper } };
let check = match({ print("S"); Wrap([1, 3, 4]) }) {
  Wrap([1, C.number, x]) => { x },
  Wrap([1, 3, x]) => { x + 10 },
  _ => { 0 }
};
let measured = (label, value) => { print(label); value };
let computed = match((2, C.Blue)) {
  (=(measured("A", 1)), C.Red) => { false },
  (=(measured("B", 2)), C.Blue) => { true },
  _ => { false }
};
let nestedComputed = match(Wrap([2, 0])) {
  Wrap([=(measured("C", 2)), 1]) => { false },
  Wrap([=(measured("D", 2)), 0]) => { true },
  _ => { false }
};
let skippedComputed = match((0, 0)) {
  (=(measured("E", 1)), =(measured("BAD", 0))) => { false },
  _ => { true }
};
let skippedShape = match(Empty) {
  Wrap(=(measured("BAD", [1]))) => { false },
  _ => { true }
};
let outside = 7;
let computedScope = match((9, 8)) {
  (Var(outside), =(outside + 1)) => { outside },
  _ => { 0 }
};
let mixedScope = match((9, 8, 7)) {
  (Var(outside), =(outside + 1), outside) => { outside },
  _ => { 0 }
};
record Row = { amount: Int32.Int, label: String };
let recordComputed = match(Row(2, "yes")) {
  .{ amount = =(C.number), label = Var(label) } => { label == "yes" },
  _ => { false }
};
let computedPartial = match { =(42) => { true } };
let realComputed = (limit: Real64.Real) => {
  match(limit / 2) { =(limit / 2) => { true }, _ => { false } }
};
let cond = (n: Int32.Int) => {
  match { =(n < 0) => { -1 }, =(n == 0) => { 0 }, _ => { 1 } } true
};
let good = pick(Wrap([1, 2, 4])) == 4 && pick(Wrap([1, 3, 4])) == 14
  && pick(Empty) == 0 && shadow(8, 7) == 8 && shadow(8, 8) == 99
  && text("yes") && !text("no") && kind(C.Red) && !kind(C.Blue)
  && negative(-2.5) && !negative(2.5) && partial(42)
  && keepScope(9, 1) == 5 && check == 14 && computed && nestedComputed && skippedComputed
  && skippedShape && computedScope == 9 && mixedScope == 9 && recordComputed
  && computedPartial(42) && realComputed(5.0)
  && cond(-2) == -1 && cond(0) == 0 && cond(2) == 1;
let main = () => { if (good) { print("ok") } else { print("FAIL") } };
''')
    subprocess.run([compiler, 'sml', out, use, constants], check=True)
    subprocess.run([compiler, 'check', out / 'use.sml'], check=True)
    run = root / 'run.sml'
    run.write_text('val _ = if Use.good then () else OS.Process.exit OS.Process.failure\n'
                   'val _ = ((Use.partial 0; OS.Process.exit OS.Process.failure) handle Match => ())\n'
                   'val _ = ((Use.computedPartial 0; OS.Process.exit OS.Process.failure) handle Match => ())\n'
                   'val _ = Use.main ()\n')
    mlb = root / 'test.mlb'
    mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(str(p) for p in [out / 'constants.sml', out / 'use.sml', run]) + '\n')
    subprocess.run(['mlton', '-output', root / 'test', mlb], check=True)
    result = subprocess.run([root / 'test'], capture_output=True)
    assert (result.returncode, result.stdout) == (0, b'SABCDEok'), result
    js = subprocess.run(['deno', 'run', '-A', wm / 'src/main.ts', 'run', use], cwd=wm, capture_output=True)
    assert js.returncode == 0 and js.stderr == b'', js
    flatten = lambda data: data.replace(b'\n', b'').replace(b'\r', b'')
    assert flatten(js.stdout) == flatten(result.stdout), (js, result)
    use.write_text('let function = (x) => { x };\nlet bad = match { function => { true }, _ => { false } };\n')
    rejected = subprocess.run([compiler, 'sml', out, use], capture_output=True)
    assert rejected.returncode != 0, rejected
    use.write_text('let [1.0] = [1.0];\n')
    rejected = subprocess.run([compiler, 'sml', out, use], capture_output=True)
    assert rejected.returncode != 0 and b'binding patterns' in rejected.stdout + rejected.stderr, rejected
    for body in [
        'let f = (x) => { x }; let bad = match { =(f) => { true }, _ => { false } };',
        'let bad = match { =(missing + 1) => { true }, _ => { false } };',
        'let bad = (=(1)) => { 1 };',
    ]:
        use.write_text(body)
        rejected = subprocess.run([compiler, 'sml', out, use], capture_output=True)
        assert rejected.returncode != 0, (body, rejected)
print('patterns: numeric/pinned nested fallthrough, scope, equality, once-only subject and Match passed')
PY
