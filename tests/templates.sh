#!/bin/sh
# Backtick strings read from Workman: text pieces join with `^`, and each `${ e }` becomes the
# text of e by its inferred type. Checked through the source Basis and MLton.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
with tempfile.TemporaryDirectory(prefix='subsetml-templates-') as directory:
    root = Path(directory)
    wm = root / 'wm'; out = root / 'sml'
    wm.mkdir(); out.mkdir()
    subprocess.run([compiler, 'wm', wm, *modules], check=True)
    use = root / 'use.wm'
    use.write_text('''let name = "Ada";
let count = 3;
let ratio = 0.5;
let ok = true;
let initial = 'A';
let big: Int64.Int = 9000000000;
let plain = `two
lines`;
let describe = (n: Int32.Int) => { `n is ${n}` };
let message = `Hi ${name}: ${count} items (${ratio}), ${ok}, ${initial}, ${big}. ${describe(7)}`;
let nested = `<${`in ${count + 1}`}|${ { let x = count; x * 2 } }> \\${not} \\`tick\\` {braces}`;
let _ = print(plain ++ "\\n" ++ message ++ "\\n" ++ nested ++ "\\n" ++ `${""}` ++ `` ++ "end");
''')
    subprocess.run([compiler, 'sml-entry', out, '--basis', wm, use], check=True)
    subprocess.run(['mlton', '-output', out / 'run', out / 'project.mlb'], check=True)
    result = subprocess.run([out / 'run'], capture_output=True, check=True)
    expected = (b'two\nlines\nHi Ada: 3 items (0.5), true, A, 9000000000. n is 7\n'
                b'<in 4|6> ${not} `tick` {braces}\nend')
    assert result.stdout == expected, result.stdout
    # A conversion SML has no counterpart for is an error, at translation time.
    use.write_text('let pair = (1, 2);\\nlet text = `${pair}`;\\n')
    failed = subprocess.run([compiler, 'sml', out, use], capture_output=True)
    assert failed.returncode != 0, failed
    # An unterminated interpolation is a lexical error.
    use.write_text('let text = `${1`;\\n')
    failed = subprocess.run([compiler, 'sml', out, use], capture_output=True)
    assert failed.returncode != 0 and b'unterminated' in failed.stderr, failed.stderr
print('templates: translation, MLton output and rejections passed')
PY
