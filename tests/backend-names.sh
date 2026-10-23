#!/bin/sh
# Reserved spellings, lexical identity, imports, recursion and label consistency.
set -eu
python3 <<'PY'
from pathlib import Path
import subprocess, tempfile
compiler = Path('bin/subsetml').resolve()
with tempfile.TemporaryDirectory(prefix='subsetml-backend-names-') as directory:
    root = Path(directory); out = root / 'sml'; out.mkdir()
    module = root / 'source.wm'
    module.write_text('''record Span = { end: Number, fn: Number };
let fn = (value) => {value + 1};
let make = Span;
let subsetmlKeyword_value0_Span = "authored";
let rec Size = (n) => {if (n <= 0) {0} else {Size(n - 1) + 1}};
''')
    use = root / 'use.wm'
    use.write_text('''from "./source.wm" import * as First;
from "./source.wm" import * as Second;
let span = First.Span(2, 4);
let field = (s: First.Span) => {s.fn};
let local = (Span) => {Span(3)};
let shadow = (n) => {let Span = (n) => {n * 2}; Span(n)};
let copied = Second.Span { ..span, fn = First.fn(8) };
let good = field(span) == 4 && copied.fn == 9 && copied.end == 2 &&
  local(Second.fn) == 4 && shadow(6) == 12 && First.Size(3) == 3 &&
  First.subsetmlKeyword_value0_Span == "authored";
''')
    subprocess.run([compiler, 'sml', out, use, module], check=True)
    subprocess.run([compiler, 'check', out / 'use.sml'], check=True)
    assert 'val Span =' not in (out / 'source.sml').read_text()
    run = root / 'run.sml'; run.write_text('val _ = if Use.good then () else OS.Process.exit OS.Process.failure\n')
    mlb = root / 'test.mlb'; mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + '\n'.join(str(p) for p in [out / 'source.sml', out / 'use.sml', run]) + '\n')
    subprocess.run(['mlton', '-output', root / 'test', mlb], check=True)
    subprocess.run([root / 'test'], check=True)
    # Variant constructor identity is also preserved after renaming its reserved spelling.
    variants = root / 'variants.wm'
    variants.write_text('''type T = | Span<Number>;
let read = (t) => {match(t) {Span(n) => {n}}};
let good = read(Span(5)) == 5;
''')
    subprocess.run([compiler, 'sml', out, variants], check=True)
    subprocess.run([compiler, 'check', out / 'variants.sml'], check=True)
    run.write_text('val _ = if Variants.good then () else OS.Process.exit OS.Process.failure\n')
    mlb.write_text('$(SML_LIB)/basis/basis.mlb\n' + str(out / 'variants.sml') + '\n' + str(run) + '\n')
    subprocess.run(['mlton', '-output', root / 'variant-test', mlb], check=True)
    subprocess.run([root / 'variant-test'], check=True)
    # Embedded SML declarations are outside the WM profile, including mixed val/rec.
    mixed = root / 'mixed.wm'
    mixed.write_text("val Span = 3.0 and rec Size = fn n => n;\n")
    rejected = subprocess.run([compiler, 'sml', out, mixed], capture_output=True)
    assert rejected.returncode != 0, rejected
    # Renaming must not hide invalid duplicate binders behind distinct safe spellings.
    bad = root / 'bad.wm'
    bad.write_text('let bad = (fn, fn) => {fn};\n')
    rejected = subprocess.run([compiler, 'sml', out, bad], capture_output=True)
    assert rejected.returncode != 0 and b'duplicate source binding fn' in rejected.stderr, rejected
    bad.write_text('let Span = (x) => {x + 1};\nlet wrong = Span("text");\n')
    rejected = subprocess.run([compiler, 'sml', out, bad], capture_output=True)
    assert rejected.returncode != 0 and b'Span' in rejected.stderr and b'subsetmlKeyword_' not in rejected.stderr, rejected
print('backend names: reserved values, constructors, aliases, shadows, recursion and labels passed')
PY
