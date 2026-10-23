#!/bin/sh
# Panic preserves bytes, evaluates its message once, and exits even when stderr fails.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess
import tempfile

repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
fixture = 'tests/basis/process_panic.sml'
subprocess.run([compiler, 'check', *modules, fixture], check=True)
subprocess.run([compiler, 'roundtrip', *modules, fixture], check=True)

def mlb_source(path):
    name = Path(path).name
    return repo / ('lib/' + name if name in {'subset_host.sml', 'subset_text_host.sml'} else path)

with tempfile.TemporaryDirectory(prefix='subsetml-panic-') as directory:
    root = Path(directory)
    wm_dir = root / 'wm'
    sml_dir = root / 'sml'
    wm_dir.mkdir()
    sml_dir.mkdir()
    # Translate checker declarations, rather than the host-specific JS adapter.
    subprocess.run([compiler, 'wm', wm_dir, *modules, fixture], check=True)
    subprocess.run([compiler, 'sml', sml_dir, *sorted(wm_dir.glob('*.wm'))], check=True)
    for name, sources in [
        ('native', [mlb_source(path) for path in modules] + [repo / fixture]),
        ('roundtrip', [mlb_source(path) if Path(path).name in {'subset_host.sml', 'subset_text_host.sml'}
                       else sml_dir / Path(path).name for path in modules] + [sml_dir / 'process_panic.sml']),
    ]:
        mlb = root / (name + '.mlb')
        mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(map(str, sources)) + '\n')
        binary = root / name
        subprocess.run(['mlton', '-output', binary, mlb], check=True)
        result = subprocess.run([binary], capture_output=True)
        assert (result.returncode, result.stdout, result.stderr) == (1, b'once', b'unreachable\x00\xff\n'), result
        # /dev/full deterministically exercises the native Result-based write failure.
        with open('/dev/full', 'wb') as stderr:
            result = subprocess.run([binary], stdout=subprocess.PIPE, stderr=stderr)
        assert (result.returncode, result.stdout) == (1, b'once'), result
print('process panic: native and reverse-translated output passed')
PY
