#!/usr/bin/env python3
"""Stage a small native MLWorks batch project to test object/image bootstrap.

Run on the desktop, then copy the output to the PS2. Does not build or transfer.
This probe covers the integer prelude, Result, List and a full-SML test driver.
"""
import argparse
from pathlib import Path
import subprocess
from mlworks_project import project_text

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--library-path', default='/home/ellie/testingstuff/mlworks-r5900/target-objects')
args = parser.parse_args()
if '\n' in args.library_path or '\r' in args.library_path:
    parser.error('library path must occupy one project-file line')
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
subprocess.run([repo / 'bin/subsetml', 'sml-target', 'mlworks', out,
                repo / 'src/subset_result.sml', repo / 'src/subset_list.sml'], check=True)
dependencies = {
    'prelude.sml': ['__int32'],
    'subset_result.sml': ['prelude'],
    'subset_list.sml': ['prelude', 'subset_result'],
}
for name, imports in dependencies.items():
    path = out / name
    path.write_text(''.join('require "' + unit + '";\n' for unit in imports) + path.read_text())
(out / 'batch_probe.sml').write_text('''require "prelude";
require "subset_result";
require "subset_list";
structure BatchProbe = struct
  fun run () =
    if SubsetList.length [true, false, true] = 3 andalso
      (case SubsetList.at (["a", "b"], 1) of SubsetResult.Ok "b" => true | _ => false)
    then print "SUBSETML_BATCH_OBJECT_OK\\n"
    else raise Fail "batch object assertion"
end
''')
(out / 'batch-probe.mlp').write_text(project_text('batch-probe.mlp',
    ['prelude.sml', 'subset_result.sml', 'subset_list.sml', 'batch_probe.sml'],
    'batch_probe.sml', args.library_path))
print(out)
