(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
*)

(* Custom Basis optional values. Absence is normal; callers choose errors explicitly. *)
structure SubsetOption = struct

  val getOr = fn (value, fallback) => case value of NONE => fallback | SOME x => x
  val isSome = fn NONE => false | SOME x => true
  val map = fn (value, f) => case value of NONE => NONE | SOME x => SOME (f x)
  val andThen = fn (value, f) => case value of NONE => NONE | SOME x => f x
  val filter = fn (value, predicate) =>
    case value of NONE => NONE | SOME x => if predicate x then value else NONE
  val toResult = fn (value, error) =>
    case value of NONE => SubsetResult.Err error | SOME x => SubsetResult.Ok x

end
