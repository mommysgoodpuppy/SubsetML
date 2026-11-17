#!/bin/sh
# Workman forms the reader spells with Basis functions: `!`, `%`, `==` on reals, and backtick
# text and `print` of any value Workman shows. The translation passes check-portable, and with
# the host adapters staged it prints what Workman prints.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
with tempfile.TemporaryDirectory(prefix='subsetml-portable-output-') as directory:
    root = Path(directory)
    wm = root / 'wm'; out = root / 'sml'
    wm.mkdir(); out.mkdir()
    subprocess.run([compiler, 'wm', wm, *modules], check=True)
    use = root / 'use.wm'
    use.write_text('''record P = { x: Int32.Int, s: String };
let flag = !(1 == 2);
let n = -7 % 3;
let r = -7.5 % 2.0;
let same = 0.1 + 0.2 != 0.3;
let c = 'x';
let _ = print(`n=${n} r=${r} flag=${flag} same=${same} c=${c} big=${1e21} small=${1.5e-7}`);
let _ = print(1, "a", true);
let _ = print();
let failed: Result<Int32.Int, String> = Err("e");
let _ = print([1, 2], Some(3.5), failed, .{ x = -1, s = "q" }, (0.1 + 0.2, [Some(1), None]));
let shout = (text: String) => { text ++ "!" };
let _ = List.forEach(["one", "two"], (word) => { print(shout(word)) });
let _ = print(`${[1, 2]} ${.{ x = -2, s = "q" }} ${(1, Some(2.5))} ${failed}`);
type Chain = End | Link<Chain>;
type Shape<T> = Dot | Box<T, T> | Tagged<String, Option<T>>;
let _ = print(Link(Link(End)), Box(1, 2), Tagged("t", Some(2.5)), Dot, `${Link(End)}`);
let _ = print(None, []);
record User = { score: Int32.Int, level: Int32.Int };
let scoreOf = user => user.score;
let _ = print(List.map([Some(1), None], Text.of), scoreOf(User(7, 1)), (a => b => a + b)(1)(2));
''')
    adapters = []
    for name, structure in [('subset_host', 'SubsetHost'), ('subset_text_host', 'SubsetTextHost'),
                            ('subset_real_host', 'SubsetRealHost')]:
        adapters += ['--native-adapter', wm / (name + '.wm'), repo / 'lib' / (name + '.sml'), structure]
    subprocess.run([compiler, 'sml-entry', out, '--basis', wm, *adapters, use], check=True)
    subprocess.run([compiler, 'check-portable', out / 'use.sml'], check=True)
    subprocess.run(['mlton', '-output', out / 'run', out / 'project.mlb'], check=True)
    result = subprocess.run([out / 'run'], capture_output=True, check=True)
    expected = (b'n=-1 r=-1.5 flag=true same=true c=x big=1e+21 small=1.5e-7\n'
                b'(1, a, true)\nvoid\n'
                b'([1, 2], Some(3.5), Err(e), { s = q, x = -1 }, (0.30000000000000004, [Some(1), None]))\n'
                b'one!\ntwo!\n'
                b'[1, 2] { s = q, x = -2 } (1, Some(2.5)) Err(e)\n'
                b'(Link(Link(End)), Box(1, 2), Tagged(t, Some(2.5)), Dot, Link(End))\n'
                b'(None, [])\n'
                b'([Some(1), None], 7, 3)\n')
    assert result.stdout == expected, result.stdout
    # A module that binds its own `print` is rejected rather than misread.
    shadow = root / 'shadow.wm'
    shadow.write_text('let print = (text: String) => { text };\nlet _ = print("x");\n')
    rejected = subprocess.run([compiler, 'sml-entry', root / 'shadow', '--basis', wm, shadow], capture_output=True)
    assert rejected.returncode != 0 and b"reads `print` as Workman's print" in rejected.stderr, rejected.stderr
    # A value with no type to show it by is an error that says what to do.
    generic = root / 'generic.wm'
    generic.write_text('let show = (x) => { `${x}` };\nlet _ = print(show(1));\nlet each = (x) => { print(x) };\n')
    rejected = subprocess.run([compiler, 'sml-entry', root / 'generic', '--basis', wm, generic], capture_output=True)
    assert rejected.returncode != 0 and b'annotate it' in rejected.stderr, rejected.stderr
print('portable output: Basis spellings pass check-portable and print as Workman does')
PY
