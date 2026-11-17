#!/bin/sh
# Inline record types, `Point{ a: Int32.Int }` in a type, hoist to record declarations before
# their statement; one inside a block stays private. Checked by running the program with MLton.
set -eu
compiler=${SUBSETML:-bin/subsetml}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/sml"
cat > "$tmp/shapes.wm" <<'WM'
let point = .{ a = 1, b = 2 }: Point{ a: Int32.Int, b: Int32.Int };
let next: Point = .{ a = point.a + 1, b = point.b };
let add = (r: AddI{ x: Int32.Int, y: Int32.Int }): AddRes{ result: Int32.Int } => {
  .{ result = r.x + r.y }
};
let again = (p: Point{ a: Int32.Int, b: Int32.Int }) => { p.a };
let nested = .{ inner = .{ v = 1 } }: Outer{ inner: Inner{ v: Int32.Int } };
let local = () => {
  let q = .{ w = 2 }: Hidden{ w: Int32.Int };
  q.w
};
let unwrap = (box: Box<t>{ value: t }) => { box.value };
let boxed = unwrap(.{ value = "box" });
let sum = add(.{ x = 2, y = 3 }).result + again(next) + nested.inner.v + local();
WM
"$compiler" sml "$tmp/sml" "$tmp/shapes.wm"
grep -q 'type hidden' "$tmp/sml/shapes.sml"
# The block-local record is private: it sits in a `local`'s hidden part.
awk '/^  local$/{l=1} l&&/type hidden/{found=1} END{exit !found}' "$tmp/sml/shapes.sml"
cat > "$tmp/run.sml" <<'SML'
val _ = print (Int.toString Shapes.sum ^ Shapes.boxed)
SML
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n' "$tmp/sml/shapes.sml" "$tmp/run.sml" > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
[ "$("$tmp/test")" = 10box ]
echo 'inline record types: hoisted, private in blocks, and run with MLton'
