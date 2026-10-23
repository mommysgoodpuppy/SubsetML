#!/bin/sh
# Actual reverse translation: let-polymorphism, field arity and keyword hygiene.
set -eu
compiler=${SUBSETML:-bin/subsetml}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/sml" "$tmp/reject"
cat > "$tmp/layouts.wm" <<'WM'
record Box<T> = { value: T };
record Carrier<A, B, C, D, E> = { fn: A -> B, map: (C, D) -> E };
record Identity<T> = { run: T -> T };
record Coupled<T> = { left: T -> T, right: T -> T };
record Converter<A, B> = { convert: A -> B };
type Wrapped<T> = | Wrapped<T>;
WM
cat > "$tmp/values.wm" <<'WM'
from "./layouts.wm" import * as Layouts;
// Force the keyword mapper to choose a different project-wide prefix.
let subsetmlKeyword_fn = "authored";
type Outcome<T, E> = Ok<T> | Err<E>;
let fn = (f) => { (r) => { match(r) {
  Ok(x) => { f(x) }, Err(e) => { Err(e) }
} } };
let map = (r, f) => { match(r) {
  Ok(x) => { Ok(f(x)) }, Err(e) => { Err(e) }
} };
let carrier = Layouts.Carrier { fn = fn, map = map };
let copied = Layouts.Carrier { ..carrier };
let fnAlias = copied.fn;
let mapAlias = copied.map;
let identity = (x) => { x };
let pair = .{ left = identity, right = identity };
let coupled = Layouts.Coupled { ..pair };
let coupledNumber: Number = coupled.left(1);
let coupledText: String = coupled.right("text");
let wrap = (x) => { Layouts.Wrapped(x) };
let wrapper = Layouts.Converter { convert = wrap };
let wrapperCopy = Layouts.Converter { ..wrapper };
let wrappedNumber: Layouts.Wrapped<Number> = wrapperCopy.convert(1);
let wrappedText: Layouts.Wrapped<String> = wrapperCopy.convert("text");
let empty = Layouts.Box { value = [] };
let numbers: Layouts.Box<List<Number>> = empty;
let texts: Layouts.Box<List<String>> = empty;
let number: Outcome<Number, String> = fnAlias((x) => { Ok(x + 1) })(Ok(1));
let text: Outcome<String, Bool> = fnAlias((x) => { Ok(x ++ "!") })(Ok("hi"));
let flag: Outcome<Bool, String> = mapAlias(Ok("value"), (_) => { true });
let stringFlag: Outcome<String, Bool> = mapAlias(Ok(true), (_) => { "ok" });
// Repeated layout parameters must still constrain the function's result.
let concrete = Layouts.Identity { run = (x) => { x + 1 } };
let main = () => {
  let ok = match(number, text, flag) {
    (Ok(a), Ok(b), Ok(c)) => { a == 2 && b == "hi!" && c }, _ => { false }
  };
  print(if (ok && concrete.run(2) == 3 && subsetmlKeyword_fn == "authored") {"carrier lowering: ok"} else {"FAILED"});
};
WM
"$compiler" sml "$tmp/sml" "$tmp/values.wm" "$tmp/layouts.wm"
printf 'val _ = Values.main ()\n' > "$tmp/run.sml"
printf '$(SML_LIB)/basis/basis.mlb\n%s\n%s\n%s\n%s\n' \
  "$PWD/lib/num.sml" "$tmp/sml/layouts.sml" "$tmp/sml/values.sml" "$tmp/run.sml" > "$tmp/test.mlb"
mlton -output "$tmp/test" "$tmp/test.mlb"
[ "$("$tmp/test")" = 'carrier lowering: ok' ]
if command -v wm >/dev/null 2>&1; then
  wm run "$tmp/values.wm" > "$tmp/result"
  [ "$(tr -d '\r\n' < "$tmp/result")" = 'carrier lowering: ok' ]
fi
cat > "$tmp/bad.wm" <<'WM'
from "./layouts.wm" import * as Layouts;
let bad = Layouts.Identity { run = (x) => { 1 } };
let wrong: String = bad.run("text");
WM
if "$compiler" sml "$tmp/reject" "$tmp/layouts.wm" "$tmp/bad.wm" > "$tmp/error" 2>&1; then
  echo 'FAIL: dropped a repeated layout type constraint'; exit 1
fi
rg -q 'expected|type|argument' "$tmp/error"
[ -z "$(ls -A "$tmp/reject")" ]
cat > "$tmp/bad.wm" <<'WM'
from "./layouts.wm" import * as Layouts;
let identity = (x) => { x };
let pair = .{ left = identity, right = identity };
let fixed: Layouts.Coupled<Number> = pair;
let bad = Layouts.Coupled { ..fixed };
let wrong: String = bad.right("text");
WM
if "$compiler" sml "$tmp/reject" "$tmp/layouts.wm" "$tmp/bad.wm" > "$tmp/error" 2>&1; then
  echo 'FAIL: generalized a concrete copied receiver'; exit 1
fi
rg -q 'expected|type|argument' "$tmp/error"
[ -z "$(ls -A "$tmp/reject")" ]
cat > "$tmp/bad.wm" <<'WM'
from "./layouts.wm" import * as Layouts;
type Outcome<T, E> = Ok<T> | Err<E>;
let fn = (f) => { (r) => { match(r) {
  Ok(x) => { f(x) }, Err(e) => { Err(e) }
} } };
let saved = fn((x) => { Ok(x) });
let holder = Layouts.Converter { convert = saved };
let alias = holder.convert;
let number: Outcome<Number, String> = alias(Ok(1));
let text: Outcome<String, String> = alias(Ok("text"));
WM
if "$compiler" sml "$tmp/reject" "$tmp/layouts.wm" "$tmp/bad.wm" > "$tmp/error" 2>&1; then
  echo 'FAIL: generalized a captured partial application'; exit 1
fi
rg -q 'expected|type|argument' "$tmp/error"
[ -z "$(ls -A "$tmp/reject")" ]
cat > "$tmp/bad.wm" <<'WM'
from "./layouts.wm" import * as Layouts;
let choose = (f) => { f };
let identity = (x) => { x };
let saved = choose(identity);
let holder = Layouts.Identity { run = saved };
let updated = Layouts.Identity { ..holder, run = (x) => { x + 1 } };
let wrong: String = saved("text");
WM
if "$compiler" sml "$tmp/reject" "$tmp/layouts.wm" "$tmp/bad.wm" > "$tmp/error" 2>&1; then
  echo 'FAIL: discarded constraints from an overwritten field'; exit 1
fi
rg -q 'expected|type|argument' "$tmp/error"
[ -z "$(ls -A "$tmp/reject")" ]
echo 'automatic carrier lowering: ok'
