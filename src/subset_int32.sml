(* @subsetml
from "./subset_numeric.sml" import * as SubsetNumeric;
from "./subset_result.sml" import * as SubsetResult;
from "./subset_string.sml" import * as SubsetString;
from "./subset_list.sml" import * as SubsetList;
from "./subset_char.sml" import * as SubsetChar;
from "./subset_real_host.sml" import * as SubsetRealHost;
from "./subset_option_value.sml" import * as SubsetOptionValue;
*)

(* Checked decimal parsing over the portable signed 32-bit integer domain. *)
structure SubsetInt32 = struct
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

  (* Inclusive ascending ranges. Stop before incrementing the final value so maximum is valid. *)
  val range = fn (first : int, last : int) =>
    SubsetList.unfold (SubsetOptionValue.SOME first, fn state =>
      case state of
        SubsetOptionValue.NONE => SubsetOptionValue.NONE
      | SubsetOptionValue.SOME value =>
          if value > last then SubsetOptionValue.NONE
          else SubsetOptionValue.SOME (value,
            if value = last then SubsetOptionValue.NONE else SubsetOptionValue.SOME (value + 1)))

  (* Visit each value directly, with the same (element, accumulator) callback as foldLeft. *)
  val foldRange = fn (first : int, last : int, initial, f) =>
    let
      val rec go = fn (value, acc) =>
        let val next = f (value, acc) in
          if value = last then next else go (value + 1, next)
        end
    in if first > last then initial else go (first, initial) end

  (* Checked arithmetic: Err Overflow where `+`, `-` or `*` would overflow. Each test runs before the
     operation and never overflows itself. *)
  val checkedAdd = fn (a : int, b : int) =>
    if (b > 0 andalso a > maximum - b) orelse (b < 0 andalso a < minimum - b) then SubsetResult.Err Overflow else SubsetResult.Ok (a + b)
  val checkedSub = fn (a : int, b : int) =>
    if (b < 0 andalso a > maximum + b) orelse (b > 0 andalso a < minimum + b) then SubsetResult.Err Overflow else SubsetResult.Ok (a - b)
  (* Magnitudes x and y are safe once neither operand is the minimum. A negative product may
     reach magnitude maximum + 1: with q = maximum div y, x = q + 1 fits exactly when
     maximum mod y = y - 1. *)
  val checkedMul = fn (a : int, b : int) =>
    if a = 0 orelse b = 0 then SubsetResult.Ok 0
    else (if a = minimum then (if b = 1 then SubsetResult.Ok a else SubsetResult.Err Overflow)
    else (if b = minimum then (if a = 1 then SubsetResult.Ok b else SubsetResult.Err Overflow)
    else
      let
        val x = if a < 0 then ~a else a
        val y = if b < 0 then ~b else b
        val q = maximum div y
      in
        if (a < 0) = (b < 0) then (if x <= q then SubsetResult.Ok (x * y) else SubsetResult.Err Overflow)
        else (if x <= q orelse (x = q + 1 andalso maximum mod y = y - 1) then SubsetResult.Ok (~x * y) else SubsetResult.Err Overflow)
      end))

  (* The real of an int, which is exact. *)
  val toReal64 = fn (value : int) => SubsetRealHost.fromInt value

  (* Exact conversion: malformed reals are InvalidInteger; out-of-range integers overflow. *)
  val fromReal64 = fn (value : real) =>
    let val fraction = SubsetRealHost.rem (value, 1.0) in
      if fraction >= 0.0 andalso fraction <= 0.0 then
        if value >= ~2147483648.0 andalso value <= 2147483647.0
        then SubsetResult.Ok (SubsetRealHost.toInt value) else SubsetResult.Err Overflow
      else SubsetResult.Err InvalidInteger
    end

  val math : int SubsetNumeric.arithmetic = {
    zero = 0, one = 1,
    add = fn (a : int, b : int) => a + b,
    mul = fn (a : int, b : int) => a * b
  }
  val carrier = math

end
