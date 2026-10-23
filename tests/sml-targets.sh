#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile

compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-targets-') as directory:
    root = Path(directory)
    def stage(target, output, sources, options=()):
        output.mkdir(exist_ok=True)
        return subprocess.run([compiler, 'sml-target', target, output, *options, *sources], capture_output=True)
    source = root / 'numbers.sml'
    source.write_text('structure Numbers = struct val hi = 2147483647 val add = fn (a,b) => a+b end\n')
    for target in ['mlton', 'mlworks']:
        out = root / target
        result = stage(target, out, [source]); assert result.returncode == 0, result.stderr
        assert 'Int32' in (out / 'prelude.sml').read_text()
        assert ('project.mlb' if target == 'mlton' else 'load.sml') in [p.name for p in out.iterdir()]
        assert 'Shell.Project.load "require_all"' in (out / 'bootstrap.sml').read_text() if target == 'mlworks' else True
    driver = root / 'driver.sml'
    driver.write_text('val _ = if Numbers.add (Numbers.hi, 0) = Numbers.hi andalso ((Numbers.add (Numbers.hi, 1); false) handle Overflow => true) then () else raise Fail "target int32"\n')
    mlb = root / 'test.mlb'; mlb.write_text('"' + str(root / 'mlton/project.mlb') + '"\n"' + str(driver) + '"\n')
    subprocess.run(['mlton', '-default-type', 'int64', '-output', root / 'run', mlb], check=True)
    subprocess.run([root / 'run'], check=True)
    # Replace the first source, whose integer prelude used to be attached to its body.
    checker = root / 'checker.sml'; checker.write_text('structure Host = struct val message = "stub" end\n')
    native = root / 'native.sml'; native.write_text('structure Host = struct val message = "native" end\n')
    alias = root / 'alias.sml'; alias.symlink_to(checker)
    out = root / 'adapted'
    result = stage('mlton', out, [checker, source], ['--adapter', alias, native]); assert result.returncode == 0, result.stderr
    assert 'native' in (out / 'checker.sml').read_text()
    driver.write_text('val _ = if Host.message = "native" andalso Numbers.hi = 2147483647 then () else raise Fail "adapter"\n')
    mlb.write_text('"' + str(out / 'project.mlb') + '"\n"' + str(driver) + '"\n')
    subprocess.run(['mlton', '-output', root / 'adapted-run', mlb], check=True)
    subprocess.run([root / 'adapted-run'], check=True)
    unused = root / 'unused.sml'; unused.write_text('val unused = true\n')
    reserved = root / 'load.sml'; reserved.write_text('val reserved = true\n')
    bad = root / 'bad.sml'; bad.write_text('val bad = 2147483648\n')
    for target, sources, options, expected in [
        ('unknown', [source], [], b'unknown SML target'),
        ('mlton', [source], ['--adapter', unused, native], b'not in the source list'),
        ('mlton', [checker], ['--adapter', checker, native, '--adapter', alias, native], b'duplicate native adapter'),
        ('mlton', [checker], ['--adapter', checker, root / 'missing.sml'], b'missing.sml'),
        ('mlworks', [reserved], [], b'reserved SML target output'),
        ('mlton', [source, bad], [], b'outside signed 32-bit range'),
    ]:
        rejected = root / 'rejected'
        result = stage(target, rejected, sources, options)
        assert result.returncode and expected in result.stderr, result.stderr
        assert not list(rejected.iterdir())
print('SML targets: int32 across host widths, canonical adapters, reserved names and atomic planning OK')
PY
