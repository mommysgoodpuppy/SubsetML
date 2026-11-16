(* @subsetml
from "./subset_option_value.sml" import * as SubsetOptionValue;
from "./subset_result_value.sml" import * as SubsetResultValue;
*)

(* Custom Basis Result. Core operations take data first; procedure adapters are curried.
   Errors are ordinary datatype values. *)
structure SubsetResult = struct
  open SubsetResultValue

  local
    open SubsetOptionValue
  in
  val map = fn (value, f) =>
    case value of Ok x => Ok (f x) | Err error => Err error

  val mapErr = fn (value, f) =>
    case value of Ok x => Ok x | Err error => Err (f error)

  val andThen = fn (value, f) =>
    case value of Ok x => f x | Err error => Err error

  (* Procedure adapters are curried so a stage can be named before it is called. *)
  val via = fn transform => fn wrapped => andThen (wrapped, transform)

  val viaErr = fn inject => fn transform => fn wrapped =>
    andThen (wrapped, fn value => mapErr (transform value, inject))

  val getOr = fn (value, fallback) =>
    case value of Ok x => x | Err error => fallback

  val isOk = fn Ok x => true | Err error => false

  val isErr = fn Ok x => false | Err error => true

  val toOption = fn Ok x => SOME x | Err error => NONE
  end

end
