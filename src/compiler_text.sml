(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
from "./subset_string.sml" import * as SubsetString;
from "./subset_natural.sml" import * as SubsetNatural;
from "./subset_bytes.sml" import * as SubsetBytes;
from "./subset_order.sml" import * as SubsetOrder;
from "./subset_list.sml" import * as SubsetList;
from "./subset_sml_escape.sml" import * as SubsetSmlEscape;
from "./subset_source.sml" import * as SubsetSource;
*)

(* Compiler-only compatibility helpers while callers migrate to checked Basis APIs.
   Assertions below rely on validated byte strings and checked/generated lexical bounds. *)
structure CompilerText = struct
  val characters = fn value => let val SubsetResult.Ok bytes = SubsetString.fromNative value in bytes end
  val stringOf = fn bytes => let val SubsetResult.Ok value = SubsetString.toNative bytes in value end
  val natural = fn value => let val SubsetResult.Ok text = SubsetNatural.toString value in text end
  val size = fn value => SubsetBytes.length (characters value)
  val less = fn (left, right) =>
    let val SubsetResult.Ok order = SubsetString.compare (left, right)
    in case order of SubsetOrder.Less => true | other => false end
  val str = fn c => stringOf [c]
  val explode = characters
  val implode = stringOf
  val map = fn f => fn value => stringOf (SubsetList.map (characters value, f))
  val translate = fn f => fn value =>
    SubsetList.foldLeft (SubsetList.map (characters value, f), "", fn (part, acc) => acc ^ part)
  val fields = fn (value, delimiter) =>
    SubsetList.map (SubsetBytes.fields (characters value, delimiter), stringOf)
  val isSuffix = fn (value, suffix) =>
    let
      val rec prefix = fn
          (xs, []) => true
        | ([], ys) => false
        | (x :: xs, y :: ys) => x = y andalso prefix (xs, ys)
    in prefix (SubsetList.reverse (characters value), SubsetList.reverse (characters suffix)) end
  val slice = fn (value, start, count) =>
    let val SubsetResult.Ok bytes = SubsetBytes.slice (characters value, start, count) in stringOf bytes end
  val drop = fn (value, count) =>
    let val SubsetResult.Ok bytes = SubsetList.drop (characters value, count) in stringOf bytes end
  val firstIs = fn (value, predicate) =>
    case characters value of [] => false | c :: rest => predicate c
  val escapeSmlChar = fn c => let val SubsetResult.Ok text = SubsetSmlEscape.escapeByte c in text end
  val escapeSmlString = fn value => let val SubsetResult.Ok text = SubsetSmlEscape.escapeString value in text end
  val source = fn value => let val SubsetResult.Ok source = SubsetSource.fromNative value in source end
  val sub = fn (source, index) => let val SubsetResult.Ok c = SubsetSource.at (source, index) in c end
  val substring = fn (source, start, count) =>
    let val SubsetResult.Ok bytes = SubsetSource.slice (source, start, count) in stringOf bytes end
end
