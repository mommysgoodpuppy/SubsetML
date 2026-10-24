(* @subsetml
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
end
