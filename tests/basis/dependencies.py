"""Audit qualified dependencies in parsed custom-library syntax (comments excluded)."""
import json
import re
import subprocess
from pathlib import Path

with open('docs/basis-dependencies.json') as source:
    modules = json.load(source)['modules']
for name, module in modules.items():
    syntax = subprocess.check_output(['bin/subsetml', 'parse', module['source']], text=True)
    # Printer-escaped string constants are data, not qualified references.
    syntax = re.sub(r'"(?:[^"\\]|\\.)*"', '', syntax)
    qualified = set(re.findall(r"\b[A-Z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_']+|\.[!%&$#+/:<=>?@\\~`^|*\-]+)+", syntax))
    opened = set(re.findall(r'\(open ([A-Z][A-Za-z0-9_]*)', syntax))
    roots = ({ref.split('.')[0] for ref in qualified} | opened) - {name}
    declared = set(module['sourceDependencies'])
    primitive_refs = set(module['primitives'])
    actual_sources = roots & modules.keys()
    actual_primitives = {ref for ref in qualified if ref.split('.')[0] not in modules and ref.split('.')[0] != name}
    if actual_sources != declared or actual_primitives != primitive_refs:
        raise SystemExit(f'{name}: dependency inventory differs: sources={sorted(actual_sources)}, primitives={sorted(actual_primitives)}')
print('custom Basis dependency inventory: ok')

# A primitive cannot silently become a new runtime obligation without an audit row.
inventory = json.loads(Path('docs/basis-dependencies.json').read_text())
expected = {f'{name}.{operation}'
            for name, adapter in inventory['hostAdapters'].items()
            for operation in adapter['operations']}
audit = Path('docs/runtime-dependencies.md').read_text()
documented = set(re.findall(r'^\| `(Subset(?:Text)?Host\.\w+)` \|', audit, re.M))
if expected != documented:
    raise SystemExit(f'runtime audit differs: missing={sorted(expected - documented)}, stale={sorted(documented - expected)}')
print('runtime dependency motivations: all host operations documented')
