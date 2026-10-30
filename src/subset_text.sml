(* @subsetml
from "./subset_order.sml" import * as SubsetOrder;
from "./subset_option_value.sml" import * as SubsetOptionValue;
from "./subset_list.sml" import * as SubsetList;
from "./subset_bytes.sml" import * as SubsetBytes;
from "./subset_result.sml" import * as SubsetResult;
from "./subset_string.sml" import * as SubsetString;
from "./subset_unicode.sml" import * as SubsetUnicode;
from "./subset_utf8.sml" import * as SubsetUtf8;
from "./subset_text_host.sml" import * as SubsetTextHost;
*)

(* Host text and strict UTF-8 bytes. Host text is the host language's own string: an SML
   string already holds UTF-8 bytes, a Workman/JS string holds UTF-16 text. Use these at a
   host edge, such as WM text entering WON; Basis byte strings convert with SubsetString. *)
structure SubsetText = struct
  datatype slice_error = InvalidIndex | UnicodeError of SubsetUnicode.error
  val toUtf8 = fn value =>
    case SubsetString.fromNative (SubsetTextHost.encodeUtf8 value) of
      SubsetResult.Err (SubsetString.NonByte offset) =>
        SubsetResult.Err (SubsetUnicode.Error (SubsetUnicode.InvalidScalar, offset))
    | SubsetResult.Ok bytes => SubsetResult.map (SubsetUtf8.decode bytes, fn scalars => bytes)

  val fromUtf8 = fn bytes =>
    SubsetResult.andThen (SubsetUtf8.decode bytes, fn scalars =>
      case SubsetString.toNative bytes of
        SubsetResult.Ok native => SubsetResult.Ok (SubsetTextHost.decodeUtf8 native)
      | SubsetResult.Err (SubsetString.NonByte offset) =>
          SubsetResult.Err (SubsetUnicode.Error (SubsetUnicode.InvalidByte, offset)))

  (* Unicode counterparts of STRING's character operations. *)
  val explode = fn value => SubsetResult.andThen (toUtf8 value, SubsetUtf8.decode)
  val implode = fn scalars => SubsetResult.andThen (SubsetUtf8.encode scalars, fromUtf8)
  val str = fn scalar => implode [scalar]
  val size = fn value => SubsetResult.map (explode value, SubsetList.length)

  (* Text indices and counts are Unicode scalars, never bytes or UTF-16 units. *)
  val extract = fn (value, start, count) =>
    SubsetResult.andThen (SubsetResult.mapErr (explode value, UnicodeError), fn scalars =>
      SubsetResult.andThen (SubsetResult.mapErr (SubsetList.drop (scalars, start), fn error => InvalidIndex), fn rest =>
        let
          val selected = case count of
              SubsetOptionValue.NONE => SubsetResult.Ok rest
            | SubsetOptionValue.SOME size =>
                SubsetResult.mapErr (SubsetList.take (rest, size), fn error => InvalidIndex)
        in SubsetResult.andThen (selected, fn chosen =>
          SubsetResult.mapErr (implode chosen, UnicodeError)) end))
  val substring = fn (value, start, count) => extract (value, start, SubsetOptionValue.SOME count)

  val map = fn (value, transform) =>
    SubsetResult.andThen (explode value, fn scalars => implode (SubsetList.map (scalars, transform)))
  val translate = fn (value, transform) =>
    SubsetResult.andThen (explode value, fn scalars =>
      SubsetResult.andThen (SubsetList.traverse (scalars, fn scalar => toUtf8 (transform scalar)), fn pieces =>
        fromUtf8 (SubsetList.concat pieces)))

  val trim = fn (value, predicate) =>
    SubsetResult.andThen (explode value, fn scalars =>
      implode (SubsetList.reverse (SubsetList.dropWhile (
        SubsetList.reverse (SubsetList.dropWhile (scalars, predicate)), predicate))))

  (* Preserve JS lexical ordering for valid text on every host. A scalar's first
     UTF-16 unit determines cross-plane order; scalar order resolves equal leads. *)
  val compare = fn (left, right) =>
    let
      val firstUnit = fn (scalar : int) =>
        if scalar < 65536 then scalar else 55296 + (scalar - 65536) div 1024
      val rec order = fn
          ([], []) => SubsetOrder.Equal
        | ([], rest) => SubsetOrder.Less
        | (rest, []) => SubsetOrder.Greater
        | (a :: xs, b :: ys) =>
            if firstUnit a < firstUnit b then SubsetOrder.Less
            else (if firstUnit a > firstUnit b then SubsetOrder.Greater
            else (if a < b then SubsetOrder.Less
            else (if a > b then SubsetOrder.Greater else order (xs, ys))))
    in SubsetResult.andThen (explode left, fn xs =>
      SubsetResult.map (explode right, fn ys => order (xs, ys))) end

  (* Valid UTF-8 substring matches cannot start or end inside a scalar encoding. *)
  val isPrefix = fn (value, prefix) =>
    SubsetResult.andThen (toUtf8 value, fn bytes =>
      SubsetResult.map (toUtf8 prefix, fn wanted => SubsetBytes.isPrefix (bytes, wanted)))
  val isSuffix = fn (value, suffix) =>
    SubsetResult.andThen (toUtf8 value, fn bytes =>
      SubsetResult.map (toUtf8 suffix, fn wanted => SubsetBytes.isSuffix (bytes, wanted)))
  val isSubstring = fn (value, needle) =>
    SubsetResult.andThen (toUtf8 value, fn bytes =>
      SubsetResult.map (toUtf8 needle, fn wanted => SubsetBytes.isSubstring (bytes, wanted)))

  (* Unicode counterpart of STRING.fields: the predicate receives scalar integers,
     once per scalar in source order, only after the entire input is validated. *)
  val fields = fn (value, delimiter) =>
    SubsetResult.andThen (toUtf8 value, fn bytes =>
      SubsetResult.andThen (SubsetUtf8.decode bytes, fn scalars =>
        let
          val rec split = fn
              ([], field, acc) => SubsetList.reverse (SubsetList.reverse field :: acc)
            | (scalar :: rest, field, acc) =>
                if delimiter scalar then split (rest, [], SubsetList.reverse field :: acc)
                else split (rest, scalar :: field, acc)
          val text = fn codes => SubsetResult.andThen (SubsetUtf8.encode codes, fromUtf8)
        in SubsetList.traverse (split (scalars, [], []), text) end))
  val tokens = fn (value, delimiter) =>
    SubsetResult.map (fields (value, delimiter), fn pieces =>
      SubsetList.filter (pieces, fn piece => piece <> ""))
end
