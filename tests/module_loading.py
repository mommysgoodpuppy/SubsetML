"""Shared local-resolution/identity fixtures, plus SubsetML metadata profile checks."""
from pathlib import Path
import json
import shutil
import subprocess
import sys

repo = Path.cwd()
root = Path(sys.argv[1]).resolve()
runner = sys.argv[2]
native = [str(repo / 'bin/subsetml')]
commands = [native] + ([['deno', 'run', '-A', runner]] if runner else [])
cases = []
reference = []


def module(directory, filename, name, sml, wm, imports=()):
    """One graph definition supplies paths/edges/order to both source spellings."""
    directory.mkdir(parents=True, exist_ok=True)
    source = directory / (filename + '.sml')
    target = directory / (filename + '.wm')
    metadata = ('(* @subsetml\n' + ''.join(
        f'from "{path}.sml" import * as {alias};\n' for path, alias in imports) + '*)\n') if imports else ''
    source.write_text(metadata + f'structure {name} = struct\n{sml}\nend\n')
    target.write_text(''.join(f'from "{path}.wm" import * as {alias};\n' for path, alias in imports) + wm + '\n')
    return source


def case(source, ok=True, message=None, common=True):
    cases.append((source, ok, message))
    if common:
        reference.append({'path': str(source.with_suffix('.wm')), 'ok': ok})


def diamond(name, alias=False, distinct=False):
    directory = root / name
    a = module(directory / ('one' if distinct else '.'), 'a', 'A',
               'datatype token = Token of real\nval token = Token 1.0',
               'type Token = | Token<Number>; let token = Token(1);')
    if distinct:
        module(directory / 'two', 'a', 'A',
               'datatype token = Token of real\nval token = Token 1.0',
               'type Token = | Token<Number>; let token = Token(1);')
    if alias:
        (directory / 'link.sml').symlink_to(a.name)
        (directory / 'link.wm').symlink_to(a.with_suffix('.wm').name)
    b = module(directory, 'b', 'B', 'val accept = fn (value : A.token) => "ok"',
               'let accept = (value: A.Token) => { "ok" };',
               [('./one/a' if distinct else './a', 'A')])
    module(directory, 'c', 'C', 'val token = A.token', 'let token = A.token;',
           [('./two/a' if distinct else ('./link' if alias else '././a'), 'A')])
    entry = module(directory, 'root', 'Root', 'val value = B.accept C.token',
                   'let value = B.accept(C.token);', [('./b', 'B'), ('./c', 'C')])
    case(entry, not distinct)
    return directory


diamond('diamond')
diamond('symlink-identity', alias=True)
diamond('same-basename-distinct', distinct=True)
hidden = diamond('hidden-transitive')
case(module(hidden, 'hidden', 'Hidden', 'val value = A.token', 'let value = A.token;',
            [('./b', 'B')]), False, 'unbound identifier')
case(module(hidden, 'private', 'Private', 'val value = B.A.token', 'let value = B.A.token;',
            [('./b', 'B')]), False, 'unbound identifier')

directory = root / 'shadow'
module(directory / 'one', 'foo', 'Foo', 'val value = 1.0', 'let value = 1;')
module(directory / 'two', 'foo', 'Foo', 'val value = "later"', 'let value = "later";')
case(module(directory, 'root', 'Root', 'val value : string = Foo.value',
            'let value: String = Foo.value;', [('./one/foo', 'Foo'), ('./two/foo', 'Foo')]))

directory = root / 'cycle'
entry = module(directory, 'a', 'A', 'val value = 1.0', 'let value = 1;', [('./b', 'B')])
module(directory, 'b', 'B', 'val value = 1.0', 'let value = 1;', [('./a', 'A')])
case(entry, False, 'import cycle:')

directory = root / 'self-cycle'
entry = module(directory, 'root', 'Root', 'val value = 1.0', 'let value = 1;', [('./link', 'Root')])
(directory / 'link.sml').symlink_to('root.sml')
(directory / 'link.wm').symlink_to('root.wm')
case(entry, False, 'import cycle:')

case(module(root / 'missing', 'root', 'Root', 'val value = 1.0', 'let value = 1;',
            [('./missing', 'Missing')]), False, 'cannot resolve import')

# URL-style dot-segment cleanup must precede filesystem symlink resolution.
directory = root / 'dot-before-symlink'
module(directory, 'a', 'A', 'val value = 1.0', 'let value = 1;')
module(directory / 'other', 'a', 'A', 'val value = "wrong"', 'let value = "wrong";')
(directory / 'other' / 'nested').mkdir()
(directory / 'link').symlink_to('other/nested', target_is_directory=True)
case(module(directory, 'root', 'Root', 'val value : real = A.value',
            'let value: Number = A.value;', [('./link/../a', 'A')]))

directory = root / 'unreachable'
entry = module(directory, 'root', 'Root', 'val value = 1.0', 'let value = 1;')
(directory / 'unused.sml').write_text('THIS IS NOT A PROGRAM')
(directory / 'unused.wm').write_text('THIS IS NOT A PROGRAM')
case(entry)

# These are intentional first-profile restrictions, not Workman resolution differences.
directory = root / 'metadata'
module(directory, 'a', 'A', 'val value = 1.0', 'let value = 1;')
case(module(directory, 'wrong', 'Wrong', 'val value = 1.0', 'let value = 1;',
            [('./a', 'Other')]), False, 'must match', common=False)
bad = directory / 'bad.sml'
bad.write_text('(* @subsetml\nfrom "./a.sml" import { value };\n*)\nval x = 1.0\n')
case(bad, False, 'expected `from', common=False)
late = directory / 'late.sml'
late.write_text('val x = 1.0\n(* @subsetml\nfrom "./a.sml" import * as A;\n*)\n')
case(late, False, 'must precede', common=False)
duplicate = directory / 'duplicate.sml'
duplicate.write_text('(* @subsetml\n*)\n(* @subsetml\n*)\nval x = 1.0\n')
case(duplicate, False, 'only one', common=False)
escaped = directory / 'escaped.sml'
escaped.write_text('(* @subsetml\nfrom "./a%2esml" import * as A;\n*)\nval x = 1.0\n')
case(escaped, False, 'explicit relative', common=False)
prose = directory / 'prose.sml'
prose.write_text('(* Example: @subsetml from "./missing.sml" import * as Missing; *)\n'
                 'val text = "(* @subsetml *)"\n')
case(prose, common=False)
extra = directory / 'extra.sml'
extra.write_text('val outside = 1.0\nstructure Extra = struct val inside = 2.0 end\n')
case(module(directory, 'extra_root', 'ExtraRoot', 'val value = Extra.inside', '',
            [('./extra', 'Extra')]), False, 'named top-level declarations', common=False)

# Every run starts outside the importing directory.
for command in commands:
    for source, ok, message in cases:
        result = subprocess.run(command + ['check', str(source)], cwd=root, capture_output=True)
        assert result.returncode == (0 if ok else 1), (command, source, result.stderr.decode(errors='replace'))
        assert not result.stdout, (source, result.stdout)
        if message:
            assert message.encode() in result.stderr, (source, result.stderr)
        if source.parent.name == 'cycle' and source.name == 'a.sml':
            route = f'{source} -> {source.parent / "b.sml"} -> {source}'
            assert route.encode() in result.stderr, result.stderr
        if source.name == 'bad.sml':
            assert b':2:1: import error:' in result.stderr, result.stderr
    result = subprocess.run(command + ['check', str(repo / 'src/main.sml')], cwd=root, capture_output=True)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
print(f'SubsetML module loading: {len(cases)} cases and compiler entry passed on {len(commands)} backends')

wm_repo = repo.parent / 'wm-mini'
if shutil.which('deno') and (wm_repo / 'src/compiler.ts').exists():
    manifest = root / 'reference.json'
    manifest.write_text(json.dumps(reference))
    harness = root / 'reference.ts'
    harness.write_text('import { checkFile } from ' + json.dumps((wm_repo / 'src/compiler.ts').as_uri()) + ';\n'
                      'const cases = JSON.parse(await Deno.readTextFile(Deno.args[0]));\n'
                      'for (const c of cases) {\n'
                      '  let ok = true; let error;\n'
                      '  try { await checkFile(c.path); } catch (e) { ok = false; error = e; }\n'
                      '  if (ok !== c.ok) throw new Error(`${c.path}: expected ${c.ok}, got ${ok}: ${error}`);\n'
                      '}\nconsole.log(`Workman reference: ${cases.length} shared module cases passed`);\n')
    result = subprocess.run(['deno', 'run', '-A', '--config', str(wm_repo / 'deno.json'),
                             str(harness), str(manifest)], cwd=wm_repo, capture_output=True)
    assert result.returncode == 0, result.stderr.decode(errors='replace')
    print(result.stdout.decode().strip())
