(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
from "./subset_list.sml" import * as SubsetList;
from "./subset_char.sml" import * as SubsetChar;
from "./subset_text_host.sml" import * as SubsetTextHost;
from "./subset_bytes.sml" import * as SubsetBytes;
*)

(* Native byte-string boundary. Extraction and reconstruction are SubsetTextHost primitives. *)
structure SubsetString = struct
  datatype error = NonByte of int
  val fromNative = fn value =>
    let
      val rec go = fn
          ([], offset, bytes) => SubsetResult.Ok (SubsetList.reverse bytes)
        | (code :: rest, offset, bytes) =>
            case SubsetChar.fromCode code of
              SubsetResult.Err error => SubsetResult.Err (NonByte offset)
            | SubsetResult.Ok c => go (rest, offset + 1, c :: bytes)
    in go (SubsetTextHost.codes value, 0, []) end

  val compare = fn (left, right) =>
    SubsetResult.andThen (fromNative left, fn xs =>
      SubsetResult.andThen (fromNative right, fn ys =>
        SubsetBytes.compareWith (xs, ys, fn offset => NonByte offset)))

  val rec concat = fn pieces =>
    case pieces of [] => "" | [value] => value | first :: second :: rest =>
      let
        val rec pairs = fn
            ([], acc) => SubsetList.reverse acc
          | ([value], acc) => SubsetList.reverse (value :: acc)
          | (left :: right :: tail, acc) => pairs (tail, (left ^ right) :: acc)
      in concat (pairs (pieces, [])) end

  val concatWith = fn (pieces, separator) =>
    case pieces of [] => "" | first :: rest =>
      let
        val rec go = fn
            ([], acc) => concat (SubsetList.reverse acc)
          | (piece :: tail, acc) => go (tail, piece :: separator :: acc)
      in go (rest, [first]) end

  val toNative = fn bytes =>
    let
      val rec go = fn
          ([], offset, codes) => SubsetResult.Ok (SubsetTextHost.fromCodes (SubsetList.reverse codes))
        | (c :: rest, offset, codes) =>
            case SubsetChar.toCode c of
              SubsetResult.Err error => SubsetResult.Err (NonByte offset)
            | SubsetResult.Ok code => go (rest, offset + 1, code :: codes)
    in go (bytes, 0, []) end
end
