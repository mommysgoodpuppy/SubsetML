#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import tempfile, subprocess
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-record-constructors-') as directory:
    root = Path(directory)
    out = root / 'sml'
    out.mkdir()
    records = root / 'records.wm'
    records.write_text('record Point = { z: Number, a: Number };\nrecord Box<T> = { value: T };\n')
    use = root / 'use.wm'
    use.write_text('''from "./records.wm" import * as R;
let mark = (label, value) => { print(label); value };
let construct = R.Point;
let point = construct(mark("Z", 2), mark("A", 3));
let text = R.Box("text");
let number = R.Box(7);
let good = point.z == 2 && point.a == 3 && text.value == "text" && number.value == 7;
''')
    subprocess.run([compiler, 'sml', out, use, records], check=True)
    subprocess.run([compiler, 'check', out / 'use.sml'], check=True)
    run = root / 'run.sml'
    run.write_text('val _ = if Use.good then () else OS.Process.exit OS.Process.failure\n')
    mlb = root / 'test.mlb'
    mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(str(p) for p in [out / 'records.sml', out / 'use.sml', run]) + '\n')
    subprocess.run(['mlton', '-output', root / 'test', mlb], check=True)
    result = subprocess.run([root / 'test'], capture_output=True)
    assert (result.returncode, result.stdout) == (0, b'ZA'), result
    use.write_text('from "./records.wm" import * as R;\nlet wrong = R.Point(1);\n')
    rejected = subprocess.run([compiler, 'sml', out, use, records], capture_output=True)
    assert rejected.returncode != 0, rejected
print('record constructors: native identity, declaration field order, generic and first-class calls passed')
PY
