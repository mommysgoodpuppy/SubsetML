#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import tempfile, subprocess
compiler = Path('bin/subsetml').resolve()
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
let negative = match { -2.5 => { true }, _ => { false } };
let partial = match { 42 => { true } };
let upper = 5;
let keepScope = match { (Var(upper), 0) => { upper }, _ => { upper } };
let check = match({ print("S"); Wrap([1, 3, 4]) }) {
  Wrap([1, C.number, x]) => { x },
  Wrap([1, 3, x]) => { x + 10 },
  _ => { 0 }
};
let good = pick(Wrap([1, 2, 4])) == 4 && pick(Wrap([1, 3, 4])) == 14
  && pick(Empty) == 0 && shadow(8, 7) == 8 && shadow(8, 8) == 99
  && text("yes") && !text("no") && kind(C.Red) && !kind(C.Blue)
  && negative(-2.5) && !negative(2.5) && partial(42)
  && keepScope(9, 1) == 5 && check == 14;
''')
    subprocess.run([compiler, 'sml', out, use, constants], check=True)
    subprocess.run([compiler, 'check', out / 'use.sml'], check=True)
    run = root / 'run.sml'
    run.write_text('val _ = if Use.good then () else OS.Process.exit OS.Process.failure\n'
                   'val _ = ((Use.partial 0; OS.Process.exit OS.Process.failure) handle Match => ())\n')
    mlb = root / 'test.mlb'
    mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(str(p) for p in [out / 'constants.sml', out / 'use.sml', run]) + '\n')
    subprocess.run(['mlton', '-output', root / 'test', mlb], check=True)
    result = subprocess.run([root / 'test'], capture_output=True)
    assert (result.returncode, result.stdout) == (0, b'S'), result
    use.write_text('let function = (x) => { x };\nlet bad = match { function => { true }, _ => { false } };\n')
    rejected = subprocess.run([compiler, 'sml', out, use], capture_output=True)
    assert rejected.returncode != 0, rejected
    use.write_text('let [1.0] = [1.0];\n')
    rejected = subprocess.run([compiler, 'sml', out, use], capture_output=True)
    assert rejected.returncode != 0 and b'binding patterns' in rejected.stdout + rejected.stderr, rejected
print('patterns: numeric/pinned nested fallthrough, scope, equality, once-only subject and Match passed')
PY
