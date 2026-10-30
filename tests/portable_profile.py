"""Exercise semantic exclusion of the SML Basis, including imports and aliases."""
from pathlib import Path
import subprocess
import tempfile
import json

compiler = Path("bin/subsetml").resolve()


def check(path, portable=True):
    return subprocess.run(
        [compiler, "check-portable" if portable else "check", path],
        capture_output=True, text=True,
    )


with tempfile.TemporaryDirectory(prefix="subsetml-portable-") as temporary:
    root = Path(temporary)
    source = root / "test.sml"
    forbidden = [
        "not", "map", "rev", "foldl", "foldr", "app", "hd", "tl", "null",
        "valOf", "isSome", "str", "concat", "implode", "explode", "print",
        "ignore", "abs", "List.map", "ListPair.zip",
        "Option.map", "String.concat", "Char.isAlpha", "Int.toString",
        "Real.isFinite", "TextIO.print", "CommandLine.arguments",
        "OS.Process.exit", "Substring.full", "Num.String.size", "LESS", "NONE", "SOME",
    ]
    for name in forbidden:
        source.write_text(f"val rejected = {name}\n")
        result = check(source)
        assert result.returncode != 0, name
        assert "unbound" in result.stderr, (name, result.stderr)
        # These really are compatibility bindings, not arbitrary unknown names.
        assert check(source, portable=False).returncode == 0, name

    for program in [
        "val rejected = [1] @ [2]",
        "val rejected = 1 before ()",
        "val rejected = (fn x => x) o (fn x => x)",
        "open List",
        "structure Alias = String\nval rejected = Alias.concat []",
        "val rejected : order = LESS",
        "val rejected : int option = 1",
        "val rejected : TextIO.instream option = NONE",
    ]:
        source.write_text(program)
        assert check(source).returncode != 0, program

    # A local implementation with the same spelling is ordinary legal source.
    source.write_text("""
structure List = struct val map = fn f => fn x => f x end
val not = fn x => if x then false else true
val answer = List.map not false
val integer = (7 div 2) + (7 mod 2)
val negative = ~integer
val text = "a" ^ "b"
val realValue = 1.0 / 2.0
""")
    result = check(source)
    assert result.returncode == 0, result.stderr

    # Library ownership is nominal and survives an explicit import; no initial
    # option identity is smuggled back into the portable environment.
    (root / "option_value.sml").write_text(Path("src/subset_option_value.sml").read_text())
    header = '(* @subsetml\nfrom "./option_value.sml" import * as SubsetOptionValue;\n*)\n'
    source.write_text(header + """
val number : int SubsetOptionValue.option = SubsetOptionValue.SOME 42
val text : string SubsetOptionValue.option = SubsetOptionValue.SOME "yes"
val absent : bool SubsetOptionValue.option = SubsetOptionValue.NONE
val answer = case number of SubsetOptionValue.SOME n => n | SubsetOptionValue.NONE => 0
val equal = number = SubsetOptionValue.SOME 42
""")
    result = check(source)
    assert result.returncode == 0, result.stderr
    source.write_text(header + """
datatype 'a option = NONE | SOME of 'a
val wrong : int SubsetOptionValue.option = SOME 42
""")
    assert check(source).returncode != 0, "unrelated source datatypes were conflated"
    source.write_text(header + """
val functions = SubsetOptionValue.SOME (fn x => x)
val wrong = functions = functions
""")
    assert check(source).returncode != 0, "source option admitted equality for functions"

    # Imported source receives the same restricted initial environment.
    (root / "bad.sml").write_text("structure Bad = struct val f = List.map end")
    source.write_text('(* @subsetml\nfrom "./bad.sml" import * as Bad;\n*)\nval x = 1')
    result = check(source)
    assert result.returncode != 0 and "List.map" in result.stderr, result.stderr

    # The option datatype can be declared by ordinary source, without a kernel hook.
    source.write_text("""
datatype 'a option = NONE | SOME of 'a
val present = SOME [1, 2]
val absent : int option = NONE
val get = fn NONE => 0 | SOME value => value
val answer = get (SOME 42)
""")
    result = check(source)
    assert result.returncode == 0, result.stderr

print("portable profile: SML Basis leakage rejected; local bindings and kernel accepted")

# Check every Basis entry graph too, so sequential checking cannot conceal a
# missing import or obtain bindings from an unrelated preceding module.
inventory = json.loads(Path("docs/basis-dependencies.json").read_text())
for module in inventory["modules"].values():
    result = check(Path(module["source"]).resolve())
    assert result.returncode == 0, result.stderr
print("portable profile: every custom Basis entry graph passes")
