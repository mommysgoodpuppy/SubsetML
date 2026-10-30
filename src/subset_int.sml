(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
from "./subset_string.sml" import * as SubsetString;
from "./subset_list.sml" import * as SubsetList;
from "./subset_char.sml" import * as SubsetChar;
*)

(* Checked decimal parsing over the portable signed 32-bit integer domain. *)
structure SubsetInt = struct
  datatype error = InvalidInteger | Overflow | StringError of SubsetString.error

  (* Accumulate negatively so the minimum integer never needs to be negated. *)
  val digits = fn (bytes, negative) =>
    let
      val last = if negative then 8 else 7
      val finish = fn (rest, acc, seen) =>
        if seen then SubsetResult.Ok (if negative then acc else 0 - acc, rest)
        else SubsetResult.Err InvalidInteger
      val rec go = fn (rest, acc : int, seen) =>
        case rest of
          [] => finish (rest, acc, seen)
        | c :: tail =>
            if SubsetChar.isDigit c then
              (case SubsetChar.toCode c of
                SubsetResult.Err error => SubsetResult.Err InvalidInteger
              | SubsetResult.Ok code =>
                  let val digit = code - 48 in
                    if acc < ~214748364 orelse (acc = ~214748364 andalso digit > last)
                    then SubsetResult.Err Overflow
                    else go (tail, acc * 10 - digit, true)
                  end)
            else finish (rest, acc, seen)
    in go (bytes, 0, false) end

  val signed = fn bytes =>
    case bytes of
      #"~" :: rest => digits (rest, true)
    | #"-" :: rest => digits (rest, true)
    | #"+" :: rest => digits (rest, false)
    | rest => digits (rest, false)

  (* SML INTEGER.fromString: skip ASCII space, parse a signed decimal prefix. *)
  val fromString = fn value =>
    SubsetResult.andThen (SubsetResult.mapErr (SubsetString.fromNative value, StringError), fn bytes =>
      SubsetResult.map (signed (SubsetList.dropWhile (bytes, SubsetChar.isSpace)), fn (number, rest) => number))

  (* Full-input decimal and unsigned decimal parsers: no whitespace or trailing data. *)
  val complete = fn result => SubsetResult.andThen (result, fn (number, rest) =>
    case rest of [] => SubsetResult.Ok number | c :: tail => SubsetResult.Err InvalidInteger)
  val parseDecimal = fn value =>
    SubsetResult.andThen (SubsetResult.mapErr (SubsetString.fromNative value, StringError), fn bytes =>
      complete (signed bytes))
  val parseNatural = fn value =>
    SubsetResult.andThen (SubsetResult.mapErr (SubsetString.fromNative value, StringError), fn bytes =>
      complete (digits (bytes, false)))
end
