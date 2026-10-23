#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
with tempfile.TemporaryDirectory(prefix='subsetml-panic-lowering-') as directory:
    root = Path(directory)
    wm = root / 'wm'
    out = root / 'sml'
    wm.mkdir(); out.mkdir()
    subprocess.run([compiler, 'wm', wm, *modules], check=True)
    runtime = wm / 'subset_process.wm'
    sources = sorted(wm.glob('*.wm'))
    use = root / 'use.wm'
    use.write_text('''let abort = Panic;
let die = (value) => { if (value) { abort("unreachable\\000\\255") } else { 1 } };
let text = (value) => { if (value) { Panic("bad") } else { "ok" } };
let Panic = (value) => { value + 1 };
let local = (Panic) => { Panic(5) };
let rec recursive = (n) => { let Panic = (x) => { x }; if (n == 0) { Panic(n) } else { recursive(n - 1) } };
let good = Panic(4) == 5 && local((x) => { x + 2 }) == 7 && recursive(1) == 0 && text(false) == "ok";
let run = () => { if (good) { die({ print("once"); true }) } else { die(true) } };
let _ = run();
''')
    subprocess.run([compiler, 'sml-entry', out, '--panic-runtime', runtime, use], check=True)
    subprocess.run([compiler, 'check', out / 'use.sml'], check=True)
    result_sources = [repo / ('lib/' + Path(p).name) if Path(p).name in {'subset_host.sml', 'subset_text_host.sml'}
                      else out / Path(p).name for p in modules if (out / Path(p).name).exists()]
    mlb = root / 'run.mlb'
    mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(map(str, result_sources + [out / 'use.sml'])) + '\n')
    subprocess.run(['mlton', '-output', root / 'run', mlb], check=True)
    result = subprocess.run([root / 'run'], capture_output=True)
    assert (result.returncode, result.stdout, result.stderr) == (1, b'once', b'unreachable\0\xff\n'), result
    with open('/dev/full', 'wb') as stderr:
        result = subprocess.run([root / 'run'], stdout=subprocess.PIPE, stderr=stderr)
    assert (result.returncode, result.stdout) == (1, b'once'), result
    # A shadowed spelling needs neither a runtime input nor an implicit dependency.
    use.write_text('let Panic = (value) => { value };\nlet result = Panic(3);\n')
    subprocess.run([compiler, 'sml', out, use], check=True)
    assert '@subsetml' not in (out / 'use.sml').read_text()
    # A same-basename unrelated module cannot select the runtime implicitly.
    impostor_dir = root / 'other'; impostor_dir.mkdir()
    impostor = impostor_dir / 'subset_process.wm'
    impostor.write_text('let panic = (value) => { value };\n')
    use.write_text('from "./other/subset_process.wm" import * as Other;\nlet value = Other.panic(3);\nlet die = Panic;\n')
    subprocess.run([compiler, 'sml', out, '--panic-runtime', runtime, use, impostor, *sources], check=True)
    generated = (out / 'use.sml').read_text()
    assert 'SubsetProcessModule.panic' in generated and 'Other.panic' not in generated, generated
    # Runtime use preserves the string constraint and requires explicit configuration.
    for body, runtime_args, expected in [
        ('let value = Panic(3);', ['--panic-runtime', runtime], b'string'),
        ('let die = Panic;', [], b'--panic-runtime'),
    ]:
        use.write_text(body)
        result = subprocess.run([compiler, 'sml', out, *runtime_args, use, *sources], capture_output=True)
        assert result.returncode != 0 and expected in result.stdout + result.stderr, result
    runtime.write_text('let panic = (value: String) => { 0 };\n')
    use.write_text('let die = Panic;\n')
    result = subprocess.run([compiler, 'sml', out, '--panic-runtime', runtime, use], capture_output=True)
    assert result.returncode != 0 and b"string -> 'a" in result.stdout + result.stderr, result
    runtime.write_text('let panic = Panic;\n')
    result = subprocess.run([compiler, 'sml', out, '--panic-runtime', runtime, use], capture_output=True)
    assert result.returncode != 0 and b'cycle' in result.stdout + result.stderr, result
print('Panic lowering: explicit runtime identity, first-class use, shadowing, dependencies and native exit passed')
PY
