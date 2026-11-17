#!/bin/sh
# Carrier groups, `Result|a, b|`, desugar as Workman does: nested `andThen` with a final `map`
# to a tuple. Checked through the source Basis and MLton.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
with tempfile.TemporaryDirectory(prefix='subsetml-carrier-groups-') as directory:
    root = Path(directory)
    wm = root / 'wm'; out = root / 'sml'
    wm.mkdir(); out.mkdir()
    subprocess.run([compiler, 'wm', wm, *modules], check=True)
    use = root / 'use.wm'
    use.write_text('''let parse = (text: String) => { if (text == "") { Err("empty") } else { Ok(text) } };
let pair = Result|parse("ab"), parse("cde")|;
let triple = Result|parse("a"), parse("bb"), parse("ccc")|;
let failed = Result|parse("x"), parse(""), parse("never")|;
let single = Result|parse("solo")|;
let two = match(pair) { Ok((Var(a), Var(b))) => { `${a}+${b}` }, Err(e) => { e } };
let three = match(triple) { Ok((Var(a), Var(b), Var(c))) => { `${a}+${b}+${c}` }, Err(e) => { e } };
let stopped = match(failed) { Ok((Var(a), Var(b), Var(c))) => { `${a}+${b}+${c}` }, Err(e) => { e } };
let one = match(single) { Ok(a) => { `${a}` }, Err(e) => { e } };
let _ = print(two ++ " " ++ three ++ " " ++ stopped ++ " " ++ one);
''')
    adapters = []
    for name, structure in [('subset_host', 'SubsetHost'), ('subset_text_host', 'SubsetTextHost'),
                            ('subset_real_host', 'SubsetRealHost')]:
        adapters += ['--native-adapter', wm / (name + '.wm'), repo / 'lib' / (name + '.sml'), structure]
    subprocess.run([compiler, 'sml-entry', out, '--basis', wm, *adapters, use], check=True)
    subprocess.run(['mlton', '-output', out / 'run', out / 'project.mlb'], check=True)
    result = subprocess.run([out / 'run'], capture_output=True, check=True)
    assert result.stdout == b'ab+cde a+bb+ccc empty solo\n', result.stdout
print('carrier groups: desugared and run with MLton')
PY
