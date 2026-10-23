#!/usr/bin/env python3
"""Stage the WM host probe for MLWorks; output files are portable to the PS2.

This is deliberately the three-module host probe, not a general MLB converter.
No transfer or remote execution is performed here.
"""
import argparse
from pathlib import Path
import shutil
import subprocess

repo = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
subprocess.run([
    repo / 'bin/subsetml', 'sml-entry', output,
    '--basis', repo / 'src',
    '--native-adapter', repo / 'lib/mlworks/checker/subset_host.wm',
    repo / 'lib/mlworks/subset_host.sml', 'SubsetHost',
    repo / 'examples/mlworks-host/probe.wm',
], check=True)
shutil.copyfile(repo / 'lib/mlworks/subset_host.sml', output / 'subset_host.native.sml')
# This loader intentionally follows the probe's fixed graph. The generated MLB
# remains the authority for desktop module scoping and adapter selection.
(output / 'bootstrap.sml').write_text('''(* One load preserves shared Basis types across all native modules. *)
Shell.Project.load "require_all";
''')
(output / 'load.sml').write_text('''use "subset_result.sml";
use "subset_host.native.sml";
use "probe.sml";
use "driver.sml";
''')
(output / 'driver.sml').write_text('''(* Full SML harness; the tested application is translated WM. *)
val bytes = CharVector.tabulate (256, Char.chr);
val () = Probe.main (".", bytes);
''')
print(output)
