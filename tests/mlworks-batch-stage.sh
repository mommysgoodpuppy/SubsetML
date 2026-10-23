#!/bin/sh
set -eu
python3 <<'PY'
from pathlib import Path
import re, subprocess, tempfile
repo=Path.cwd()
with tempfile.TemporaryDirectory() as directory:
 out=Path(directory)
 subprocess.run(['python3',repo/'scripts/stage-mlworks-batch-compiler.py',out],check=True)
 names=(out/'units.txt').read_text().splitlines()
 assert names[0]=='prelude' and names[-1]=='main' and len(names)==len(set(names))
 seen={'require_all'}
 for name in names:
  text=(out/(name+'.sml')).read_text()
  imports=re.findall(r'^require "([^"]+)";',text,re.M)
  assert imports and set(imports)<=seen,(name,set(imports)-seen)
  seen.add(name)
 assert not (out/'main.sml').read_text().rstrip().endswith('val _ = Main.main ()')
 assert '  Files '+str(len(names))+' 0\n' in (out/'compiler.mlp').read_text()
 assert (out/'run-memory-limited.sh').is_file() and (out/'run-subsetml.sh').is_file()
print('Batch stage: dependency order, listed units, coherent Basis and deferred CLI OK')
PY
