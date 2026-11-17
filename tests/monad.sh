#!/bin/sh
# Monad functions are field accesses on a Carrier record from the Basis, and a bare namespace in
# value position stands for its carrier. Checked through the source Basis and MLton.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
with tempfile.TemporaryDirectory(prefix='subsetml-monad-') as directory:
    root = Path(directory)
    wm = root / 'wm'; out = root / 'sml'
    wm.mkdir(); out.mkdir()
    subprocess.run([compiler, 'wm', wm, *modules], check=True)
    use = root / 'use.wm'
    use.write_text('''type Error = | ParseFailure<String> | Negative<Int32.Int>;
let parse = (text: String) => { if (text == "12") { Ok(12) } else { Err(text) } };
let checkSign = (n: Int32.Int) => { if (n >= 0) { Ok(n) } else { Err(n) } };
let show = (r: Result<Int32.Int, Error>) => { match(r) { Ok(n) => { `${n}` }, Err(ParseFailure(t)) => { `parse ${t}` }, Err(Negative(n)) => { `neg ${n}` } } };
let parseStage = Monad.viaErr(Result)(ParseFailure)(parse);
let signStage = Monad.viaErr(Result)(Negative)(checkSign);
let staged = (text) => { Ok(text) :> parseStage :> signStage };
let doubled = Monad.map(Ok(4), Result, (n) => { n * 2 });
let chained = Monad.andThen(Ok(5), Result, (n) => { if (n > 3) { Ok(n) } else { Err("small") } });
let renamed = Monad.mapErr(Err("x"), Result, (e) => { e ++ "!" });
let all = Monad.traverse([1, 2, 3], Result, (n) => { Ok(n * 10) });
let stopped = Monad.traverse([1, -2, 3], Result, checkSign);
let domain = Result;
let summed = Monad.map(domain.map2(Ok(1), Ok(2), (a, b) => { a + b }), domain, (n) => { n + domain.succeed(0) :> match { Ok(z) => { z }, Err(_) => { 0 } } });
let viaStage = Monad.via(Result.carrier)((n) => { Ok(n + 1) });
let text = (r: Result<Int32.Int, String>) => { match(r) { Ok(n) => { `${n}` }, Err(e) => { e } } };
let list = (r: Result<List<Int32.Int>, Int32.Int>) => { match(r) { Ok(ns) => { String.concatWith(List.map(ns, (n: Int32.Int) => { `${n}` }), ",") }, Err(n) => { `stop ${0 - n}` } } };
let _ = print(show(staged("12")) ++ " " ++ show(staged("x")) ++ " " ++ text(doubled) ++ " " ++ text(chained) ++ " " ++ text(renamed) ++ " " ++ list(all) ++ " " ++ list(stopped) ++ " " ++ text(summed) ++ " " ++ text(viaStage(Ok(1))));
''')
    adapters = []
    for name, structure in [('subset_host', 'SubsetHost'), ('subset_text_host', 'SubsetTextHost'),
                            ('subset_real_host', 'SubsetRealHost')]:
        adapters += ['--native-adapter', wm / (name + '.wm'), repo / 'lib' / (name + '.sml'), structure]
    subprocess.run([compiler, 'sml-entry', out, '--basis', wm, *adapters, use], check=True)
    subprocess.run(['mlton', '-output', out / 'run', out / 'project.mlb'], check=True)
    result = subprocess.run([out / 'run'], capture_output=True, check=True)
    assert result.stdout == b'12 parse x 8 5 x! 10,20,30 stop 2 3 2\n', result.stdout
print('monad: Basis carriers and bare namespaces run with MLton')
PY
