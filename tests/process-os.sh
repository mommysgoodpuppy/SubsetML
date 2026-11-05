#!/bin/sh
# OS.Process across targets: shell commands, environment and exit codes.
set -eu
python3 <<'PY'
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

repo = Path.cwd()
compiler = repo / 'bin/subsetml'
modules = subprocess.check_output(['python3', 'scripts/basis-sources.py'], text=True).split()
fixture = 'tests/basis/process_os.sml'
subprocess.run([compiler, 'check', *modules, fixture], check=True)
subprocess.run([compiler, 'roundtrip', *modules, fixture], check=True)
environment = {k: v for k, v in os.environ.items() if k != 'SUBSET_PROCESS_UNSET'}
environment['SUBSET_PROCESS_PROBE'] = 'a b'

def expect(name, command):
    result = subprocess.run(command, capture_output=True, env=environment)
    assert (result.returncode, result.stdout) == (3, b'ran'), (name, result)

def host_source(path):
    name = Path(path).name
    return repo / ('lib/' + name if name in {'subset_host.sml', 'subset_text_host.sml'} else path)

with tempfile.TemporaryDirectory(prefix='subsetml-process-') as directory:
    root = Path(directory)
    wm_dir = root / 'wm'
    sml_dir = root / 'sml'
    wm_dir.mkdir()
    sml_dir.mkdir()
    subprocess.run([compiler, 'wm', wm_dir, *modules, fixture], check=True)
    subprocess.run([compiler, 'sml', sml_dir, *sorted(wm_dir.glob('*.wm'))], check=True)
    for name, sources in [
        ('native', [host_source(path) for path in modules] + [repo / fixture]),
        ('roundtrip', [host_source(path) if Path(path).name in {'subset_host.sml', 'subset_text_host.sml'}
                       else sml_dir / Path(path).name for path in modules] + [sml_dir / 'process_os.sml']),
    ]:
        mlb = root / (name + '.mlb')
        mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(map(str, sources)) + '\n')
        subprocess.run(['mlton', '-output', root / name, mlb], check=True)
        expect(name, [root / name])
    if shutil.which('wm'):
        subprocess.run(['sh', 'scripts/stage-text-host.sh', wm_dir], check=True)
        expect('workman', ['wm', 'run', wm_dir / 'process_os.wm'])
print('OS.Process: shell commands, environment and exit codes passed on every target')
PY
