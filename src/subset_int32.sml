(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
from "./subset_string.sml" import * as SubsetString;
from "./subset_list.sml" import * as SubsetList;
from "./subset_char.sml" import * as SubsetChar;
from "./subset_option_value.sml" import * as SubsetOptionValue;
from "./subset_real_host.sml" import * as SubsetRealHost;
*)

(* Checked decimal parsing over the portable signed 32-bit integer domain. *)
structure SubsetInt32 = struct
  open SubsetOptionValue

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

  (* Workman's `%`: the remainder of division truncated toward zero, with the dividend's sign.
     Floored `mod` differs from it exactly when the remainder is nonzero and the signs differ. *)
  val rem = fn (dividend : int, divisor : int) =>
    let val m = dividend mod divisor in
      if m <> 0 andalso ((dividend < 0) <> (divisor < 0)) then m - divisor else m
    end

  (* Decimal text as Workman writes it, `-12` rather than SML's `~12`. Digits are taken from
     the nonpositive value, so the minimum integer needs no negation. *)
  val toString = fn (value : int) =>
    let
      val rec digit = fn (index, entries) =>
        case entries of [] => "" | first :: rest =>
          if index <= 0 then first else digit (index - 1, rest)
      val rec go = fn (remaining, acc) =>
        let
          val residue = remaining mod 10
          val text = digit (if residue = 0 then 0 else 10 - residue,
            ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
          val next = if residue = 0 then remaining div 10 else remaining div 10 + 1
        in if next = 0 then text :: acc else go (next, text :: acc) end
    in
      if value < 0 then SubsetString.concat ("-" :: go (value, []))
      else SubsetString.concat (go (~value, []))
    end

  val minimum = ~2147483648
  val maximum = 2147483647

  (* Checked arithmetic: NONE where `+`, `-` or `*` would overflow. Each test runs before the
     operation and never overflows itself. *)
  val checkedAdd = fn (a : int, b : int) =>
    if (b > 0 andalso a > maximum - b) orelse (b < 0 andalso a < minimum - b) then NONE else SOME (a + b)
  val checkedSub = fn (a : int, b : int) =>
    if (b < 0 andalso a > maximum + b) orelse (b > 0 andalso a < minimum + b) then NONE else SOME (a - b)
  (* Magnitudes x and y are safe once neither operand is the minimum. A negative product may
     reach magnitude maximum + 1: with q = maximum div y, x = q + 1 fits exactly when
     maximum mod y = y - 1. *)
  val checkedMul = fn (a : int, b : int) =>
    if a = 0 orelse b = 0 then SOME 0
    else (if a = minimum then (if b = 1 then SOME a else NONE)
    else (if b = minimum then (if a = 1 then SOME b else NONE)
    else
      let
        val x = if a < 0 then ~a else a
        val y = if b < 0 then ~b else b
        val q = maximum div y
      in
        if (a < 0) = (b < 0) then (if x <= q then SOME (x * y) else NONE)
        else (if x <= q orelse (x = q + 1 andalso maximum mod y = y - 1) then SOME (~x * y) else NONE)
      end))

  (* The real of an int, which is exact. *)
  val toReal64 = fn (value : int) => SubsetRealHost.fromInt value

  (* The int a real is, when it is integral and in range: NONE for fractions, NaN, infinities
     and reals outside the int range. *)
  val fromReal64 = fn (value : real) =>
    let val fraction = SubsetRealHost.rem (value, 1.0) in
      if value >= ~2147483648.0 andalso value <= 2147483647.0 andalso
         fraction >= 0.0 andalso fraction <= 0.0
      then SOME (SubsetRealHost.toInt value) else NONE
    end
end
