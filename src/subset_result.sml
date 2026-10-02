(* Custom Basis Result. Data comes first; errors are ordinary datatype values. *)
structure SubsetResult = struct

  datatype ('a, 'e) result = Ok of 'a | Err of 'e

  val map = fn (value, f) =>
    case value of Ok x => Ok (f x) | Err error => Err error

  val mapError = fn (value, f) =>
    case value of Ok x => Ok x | Err error => Err (f error)

  val andThen = fn (value, f) =>
    case value of Ok x => f x | Err error => Err error

  val getOr = fn (value, fallback) =>
    case value of Ok x => x | Err error => fallback

  val isOk = fn Ok x => true | Err error => false

  val toOption = fn Ok x => SOME x | Err error => NONE

end
