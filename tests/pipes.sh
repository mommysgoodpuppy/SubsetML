#!/bin/sh
# WM-only pipe syntax lowers to existing SubsetML applications.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess
import tempfile

repo = Path.cwd()
compiler = repo / 'bin/subsetml'
wm = repo.parent / 'wm-mini'

def run(args, **kwargs):
    result = subprocess.run(list(map(str, args)), capture_output=True, **kwargs)
    assert result.returncode == 0, (args, result.stdout.decode(), result.stderr.decode())
    return result

with tempfile.TemporaryDirectory(prefix='subsetml-pipes-') as directory:
    root = Path(directory)
    out = root / 'sml'
    out.mkdir()
    (root / 'math.wm').write_text('let add = (a: I32, b: I32) => { a + b };\n')
    source = root / 'pipe.wm'
    source.write_text('''from "./math.wm" import * as Math;
let inc = (x: I32) => { x + 1 };
let sub = (x: I32, y: I32) => { x - y };
let curried = (n: I32) => (x) => { x + n };
let ternary = (a: I32, b: I32, c: I32) => { a + b + c };
let takesUnit = (x: I32) => { x + 10 };
let length = (xs: List<I32>) => { match(xs) { [a, b] => { a + b }, _ => { 0 } } };
let base = 3 :> inc :> Math.add(4);
let inserted = 10 :> sub(3);
let many = 1 :> ternary(2, 3);
let emptyCall = 3 :> takesUnit();
let grouped = 3 :> (curried(4));
let spaced = 3 :> curried 4;
let commented = 3 :> curried/*gap*/4;
let lambda = 3 :> ((x) => { x + 4 });
let returned = 3 :> curried(4)();
let spaceLambda = (f) => (x) => { f(x) };
let adapted = 3 :> spaceLambda (x) => { x + 4 };
let leftAssoc = 10 :> sub(1) :> sub(2);
let precedence = 1 + 2 :> inc * 3;
let groupedInput = (1 + 2) :> inc;
let unary = -2 :> inc;
let logic = !false :> ((x) => { !x });
let appended: List<I32> = [1] :> List.append([2]);
let pair = (1, 2) :> ((a, b) => { a + b });
let nested = 1 :> Math.add(2 :> inc);
let asArgument = inc(3 :> inc);
let afterGroup = 3 :> (curried)(4)();
let standaloneSpace = curried 4;
let spaceChain = 3 :> curried 4 :> inc;
let tupleFirst = ((a, b): (I32, I32), n: I32) => { a + b + n };
let tupleInserted = (1, 2) :> tupleFirst(3);
let good = base == 8 && inserted == 7 && many == 6 && emptyCall == 13
  && grouped == 7 && spaced == 7 && commented == 7 && lambda == 7
  && returned == 7 && adapted == 7 && leftAssoc == 7
  && precedence == 10 && groupedInput == 4 && unary == -3 && !logic
  && length(appended) == 3 && pair == 3 && nested == 4 && asArgument == 5
  && afterGroup == 7 && standaloneSpace(3) == 7 && spaceChain == 8 && tupleInserted == 6;
let input = () => { print("input"); (3: I32) };
let arg = () => { print("arg"); (4: I32) };
let factory = (n: I32) => {
  print("factory");
  (x) => { print("apply"); x + n }
};
let groupedEffects = input() :> (factory(arg()));
let spacedEffects = input() :> factory 4;
let makePair = (label) => { print(label); (a: I32, b: I32) => { a + b } };
let insertedEffects = input() :> makePair("callee")(arg());
let labelled = (label) => { print(label); (x: I32) => { x + 1 } };
let chainedEffects = input() :> (labelled("first")) :> (labelled("second"));
let main = () => {
  if (good && groupedEffects == 7 && spacedEffects == 7 && insertedEffects == 7 && chainedEffects == 5) {
    print("ok")
  } else { print("FAIL") }
};
''')
    run([compiler, 'sml-entry', out, source])
    (out / 'driver.sml').write_text('val _ = Pipe.main ()\n')
    (out / 'run.mlb').write_text('project.mlb\ndriver.sml\n')
    run(['mlton', '-output', root / 'native', out / 'run.mlb'])
    native = run([root / 'native']).stdout
    js = run(['deno', 'run', '-A', wm / 'src/main.ts', 'run', source], cwd=wm).stdout
    expected = b'arg\nfactory\ninput\napply\nfactory\ninput\napply\ncallee\ninput\narg\nsecond\nfirst\ninput\nok\n'
    flatten = lambda data: data.replace(b"\n", b"").replace(b"\r", b"")
    assert flatten(native) == flatten(js) == flatten(expected), (native, js, expected)
    # SML -> WM continues to print ordinary calls, not pipe syntax.
    printed = root / 'wm'
    printed.mkdir()
    run([compiler, 'wm', printed, out / 'math.sml', out / 'pipe.sml'])
    assert ':>' not in (printed / 'pipe.wm').read_text()
    for expression in ('3 :> .field', '3 :> .method()', '3 :>',
                       '3 :> Math.add(true)', '3 :> (4)', '3 :> inc(1)',
                       '3 :> curried(4)', '3: >inc'):
        rejected = root / 'reject'
        rejected.mkdir(exist_ok=True)
        bad = root / 'bad.wm'
        bad.write_text(source.read_text().split('let base =')[0] + 'let bad = ' + expression + ';\n')
        result = subprocess.run([str(compiler), 'sml-entry', str(rejected), str(bad)], capture_output=True)
        assert result.returncode != 0, expression
        assert not list(rejected.iterdir()), expression
        if ':> .' in expression:
            assert b'receiver pipes' in result.stdout + result.stderr, result
print('pipes: syntax forms, precedence, currying, effects, JS/native parity, rejection and one-way printing passed')
PY
