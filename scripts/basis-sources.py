"""Print the portable Basis graph, including checker declarations for its host adapters."""
import json
from pathlib import Path
modules = json.loads(Path('docs/basis-dependencies.json').read_text())['modules']
files = ['src/subset_text_host.sml']
for name, module in modules.items():
    files.append(module['source'])
    if name == 'SubsetResult':
        files.append('src/subset_host.sml')
print(' '.join(files))
