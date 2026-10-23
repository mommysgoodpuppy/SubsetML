#!/usr/bin/env python3
"""Bootstrap SubsetML's own ordered source list through its SML target command.

The existing compiler MLB is the source-order manifest. This helper understands
that flat file only; SML target generation lives in SubsetML, not Python.
"""
import argparse
from pathlib import Path
import subprocess

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('target', choices=['mlton', 'mlworks'])
parser.add_argument('output', type=Path)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
sources = []
for entry in (repo / 'src/subsetml.mlb').read_text().splitlines():
    if entry in ['$(SML_LIB)/basis/basis.mlb', '../lib/num.sml']:
        continue
    if entry in ['../lib/subset_text_host.sml', '../lib/subset_host.sml']:
        entry = Path(entry).name
    if not entry.endswith('.sml'):
        raise SystemExit('unsupported compiler manifest entry: ' + entry)
    sources.append(repo / 'src' / entry)
subprocess.run([
    repo / 'bin/subsetml', 'sml-target', args.target, output,
    '--adapter', repo / 'src/subset_text_host.sml', repo / 'lib/subset_text_host.sml',
    '--adapter', repo / 'src/subset_host.sml', repo / 'lib/sml-basis/subset_host.sml',
    *sources,
], check=True)
print(output)
