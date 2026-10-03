#!/bin/sh
set -eu
python <<'PY'
from pathlib import Path
import shutil, subprocess, tempfile
native = [str(Path('bin/subsetml').resolve())]
workman = ['wm', 'run', str(Path('src/main.wm').resolve()), '--'] if shutil.which('wm') else None
def run(command, args):
    return subprocess.run(command + [str(x) for x in args], capture_output=True)
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / 'sample.sml'
    source.write_text('''structure Sample = struct
(* Byte literals and a polymorphic constructor. *)
datatype 'a box = Box of 'a
val unpack = fn Box value => value
val answer = unpack (Box 42.0)
val bytes = "\\000\\127\\255"
end
''')
    # Many tokens exercise scanning without growing a mutual-recursion stack.
    long_source = root / 'long.sml'
    long_source.write_text('structure Long = struct\nval values = [' +
                           ', '.join(['1.0'] * 6000) + ']\nend\n')
    for command in [native] + ([workman] if workman else []):
        scanned = run(command, ['parse', long_source])
        assert scanned.returncode == 0, scanned.stderr.decode(errors='replace')
    # An invalid phrase still scans every token before reporting its parse error.
    # This isolates the Workman lexer from deeply nested AST elaboration.
    long_wm = root / 'long.wm'
    long_wm.write_text('let value = ' + 'token ' * 6000 + ';\n')
    for command in [native] + ([workman] if workman else []):
        sml_dir = root / ('long-sml-' + ('native' if command == native else 'workman'))
        sml_dir.mkdir()
        rejected = run(command, ['sml', sml_dir, long_wm])
        assert rejected.returncode == 1 and b'expected' in rejected.stderr, rejected.stderr.decode(errors='replace')
    bad = root / 'bad.sml'
    bad.write_text('val rejected = "a" < "b"\n')
    for action in ['check', 'parse', 'fmt', 'roundtrip']:
        expected = run(native, [action, source])
        assert expected.returncode == 0, expected.stderr.decode(errors='replace')
        if workman:
            actual = run(workman, [action, source])
            assert (actual.returncode, actual.stdout, actual.stderr) == (0, expected.stdout, expected.stderr), (action, actual.stderr.decode(errors='replace'))
    for command in [native] + ([workman] if workman else []):
        for path in [bad, root / 'missing.sml']:
            failed = run(command, ['check', path])
            assert failed.returncode == 1 and failed.stderr and not failed.stdout, (path, failed)
    lexical = root / 'lexical.sml'
    lexical.write_text('(* input *)\nval x = "unterminated')
    syntax = root / 'syntax.sml'
    syntax.write_text('val x =\n')
    multiple = root / 'multiple.sml'
    multiple.write_text('structure A = struct end\nstructure B = struct end\n')
    for path, location, message in [
        (lexical, ':2:9: lex error:', 'unterminated string constant'),
        (syntax, ':2:1: parse error:', 'expected'),
        (multiple, ':2:1: parse error:', 'a file may contain only one structure'),
    ]:
        expected = run(native, ['check', path])
        assert expected.returncode == 1 and not expected.stdout
        assert (str(path) + location).encode() in expected.stderr and message.encode() in expected.stderr, expected.stderr
        if workman:
            actual = run(workman, ['check', path])
            assert (actual.returncode, actual.stdout, actual.stderr) == (1, b'', expected.stderr), actual.stderr
    # Report every loading failure; never render a successfully parsed file on failure.
    for command in [native] + ([workman] if workman else []):
        failed = run(command, ['fmt', root / 'missing.sml', lexical, source, syntax])
        assert failed.returncode == 1 and not failed.stdout, failed
        for path in [root / 'missing.sml', lexical, syntax]:
            assert str(path).encode() in failed.stderr, failed.stderr
        assert failed.stderr.index(b'missing.sml') < failed.stderr.index(b'lexical.sml') < failed.stderr.index(b'syntax.sml')
    outputs = []
    for index, command in enumerate([native] + ([workman] if workman else [])):
        wm_dir = root / f'wm-{index}'
        sml_dir = root / f'sml-{index}'
        wm_dir.mkdir(); sml_dir.mkdir()
        translated = run(command, ['wm', wm_dir, source])
        assert translated.returncode == 0, translated.stderr.decode(errors='replace')
        recovered = run(command, ['sml', sml_dir, wm_dir / 'sample.wm'])
        assert recovered.returncode == 0, recovered.stderr.decode(errors='replace')
        outputs.append(((wm_dir / 'sample.wm').read_bytes(), (sml_dir / 'sample.sml').read_bytes()))
    assert all(value == outputs[0] for value in outputs)
print('compiler CLI across targets: ok')
PY
