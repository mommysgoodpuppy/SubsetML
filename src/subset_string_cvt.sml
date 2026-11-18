(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
from "./subset_list.sml" import * as SubsetList;
from "./subset_string.sml" import * as SubsetString;
from "./subset_text.sml" import * as SubsetText;
*)

(* SML STRING_CVT padding, data first. Text widths count Unicode scalars. *)
structure SubsetStringCvt = struct
  val repeat32 = fn (piece, count : int) =>
    let val rec go = fn (left, acc) =>
      if left <= 0 then SubsetString.concat acc else go (left - 1, piece :: acc)
    in go (count, []) end
  val pad32 = fn (value, width : int, piece, length : int, left) =>
    if width <= length then value
    else let val padding = repeat32 (piece, width - length)
      in if left then padding ^ value else value ^ padding end

  val padLeft32 = fn (value, width, c) =>
    SubsetResult.andThen (SubsetString.fromNative value, fn bytes =>
      SubsetResult.map (SubsetString.str c, fn piece =>
        pad32 (value, width, piece, SubsetList.length32 bytes, true)))
  val padRight32 = fn (value, width, c) =>
    SubsetResult.andThen (SubsetString.fromNative value, fn bytes =>
      SubsetResult.map (SubsetString.str c, fn piece =>
        pad32 (value, width, piece, SubsetList.length32 bytes, false)))
  val padTextLeft32 = fn (value, width, scalar) =>
    SubsetResult.andThen (SubsetText.explode value, fn scalars =>
      SubsetResult.map (SubsetText.str scalar, fn piece =>
        pad32 (value, width, piece, SubsetList.length32 scalars, true)))
  val padTextRight32 = fn (value, width, scalar) =>
    SubsetResult.andThen (SubsetText.explode value, fn scalars =>
      SubsetResult.map (SubsetText.str scalar, fn piece =>
        pad32 (value, width, piece, SubsetList.length32 scalars, false)))
end
