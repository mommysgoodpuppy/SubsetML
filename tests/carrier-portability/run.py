"""Compare WM's carrier semantics with explicit portable SML encodings.
Run from the repository root: python3 tests/carrier-portability/run.py
Requires the sibling wm-mini checkout, wm, deno, and MLton. It changes neither compiler.
"""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
fixtures = Path(__file__).resolve().parent
cases = {
    'shared': True, 'procedure': True, 'partial': False, 'eta': True,
    'parameter': False, 'copy': False, 'projection': False, 'copy_eta': True,
}
reference = subprocess.run([
    'deno', 'run', '-A', '--config', str(repo.parent / 'wm-mini/deno.json'),
    str(fixtures / 'probe.ts'),
], capture_output=True, text=True)
assert reference.returncode == 0, reference.stderr
print(reference.stdout, end='')
with tempfile.TemporaryDirectory(prefix='subset-carriers-') as directory:
    output = Path(directory)
    for name, accepted in cases.items():
        mlb = output / (name + '.mlb')
        mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + str(fixtures / 'carrier_kernel.sml') + '\n'
                       + str(fixtures / (name + '.sml')) + '\n')
        executable = output / name
        result = subprocess.run(['mlton', '-output', str(executable), str(mlb)], capture_output=True, text=True)
        assert (result.returncode == 0) == accepted, (name, result.stderr)
        print(f'{name}: MLton {"accepts" if accepted else "rejects"}')
        # Independently check that the accepted SML also belongs to SubsetML.
        checked = subprocess.run([str(repo / 'bin/subsetml'), 'check', str(fixtures / 'carrier_kernel.sml'),
                                  str(fixtures / (name + '.sml'))], capture_output=True, text=True)
        assert (checked.returncode == 0) == accepted, (name, checked.stderr)
        if accepted:
            expected = name + ': ok'
            native = subprocess.check_output([str(executable)], text=True).strip()
            wm = subprocess.check_output(['wm', 'run', str(fixtures / (name + '.wm'))], text=True).strip()
            assert native == expected and wm == expected, (name, native, wm)
    # A separate translation spelling issue: fn is a valid WM label and an SML keyword.
    keyword = output / 'keyword.wm'
    keyword.write_text('record One = { fn: Number -> Number };\n'
                       'let value = One { fn = (x) => { x } };\n')
    generated = output / 'generated'
    generated.mkdir()
    translated = subprocess.run([str(repo / 'bin/subsetml'), 'sml', str(generated), str(keyword)],
                                capture_output=True, text=True)
    assert translated.returncode == 0, translated.stderr
    mlb = output / 'keyword.mlb'
    mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + str(generated / 'keyword.sml') + '\n')
    result = subprocess.run(['mlton', '-stop', 'tc', str(mlb)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    print('fn label: keyword-safe generated SML passes MLton syntax checking')
roundtrip = subprocess.run([str(repo / 'bin/subsetml'), 'roundtrip', str(fixtures / 'carrier_kernel.sml'),
                            str(fixtures / 'shared.sml')], capture_output=True, text=True)
assert roundtrip.returncode == 0, roundtrip.stderr
print('Portable kernel/shared case: source-to-WM-to-SML round trip passes')
print('Carrier portability investigation: expected typing and runtime results confirmed')
