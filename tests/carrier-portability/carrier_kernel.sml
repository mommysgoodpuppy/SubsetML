(* A source implementation of WM's Result carrier, with fn renamed fn_ for SML.
   All carrier parameters are rank-1. The alias fixes the receiver's complete record shape. *)
structure CarrierKernel = struct
  datatype ('a, 'e) result = Ok of 'a | Err of 'e
  type ('fa, 'fr, 'ea, 'er, 'sa, 'sr, 'mc, 'mt, 'mr, 'ml, 'mright, 'mf, 'mresult, 'ac, 'at, 'ar, 'ec, 'et, 'eresult) carrier = {
    fn_: 'fa -> 'fr,
    fnError: 'ea -> 'er,
    succeed: 'sa -> 'sr,
    map: 'mc * 'mt -> 'mr,
    map2: 'ml * 'mright * 'mf -> 'mresult,
    andThen: 'ac * 'at -> 'ar,
    mapErr: 'ec * 'et -> 'eresult
  }
  val succeed = fn value => Ok value
  val map = fn (result, f) =>
    case result of Ok value => Ok (f value) | Err error => Err error
  val andThen = fn (result, f) =>
    case result of Ok value => f value | Err error => Err error
  val fn_ = fn f => fn result => andThen (result, f)
  val mapErr = fn (result, f) =>
    case result of Ok value => Ok value | Err error => Err (f error)
  val fnError = fn inject => fn f =>
    fn_ (fn value => mapErr (f value, inject))
  val map2 = fn (left, right, f) =>
    case (left, right) of
      (Ok a, Ok b) => Ok (f (a, b))
    | (Err error, _) => Err error
    | (_, Err error) => Err error

  (* Identifiers as fields keep this binding non-expansive. *)
  val carrier = {
    fn_ = fn_, fnError = fnError, succeed = succeed,
    map = map, map2 = map2, andThen = andThen, mapErr = mapErr
  }
  val via = fn (domain: ('fa, 'fr, 'ea, 'er, 'sa, 'sr, 'mc, 'mt, 'mr, 'ml, 'mright, 'mf, 'mresult, 'ac, 'at, 'ar, 'ec, 'et, 'eresult) carrier) => fn f => (#fn_ domain) f
  val viaError = fn (domain: ('fa, 'fr, 'ea, ('handler -> 'handled), 'sa, 'sr, 'mc, 'mt, 'mr, 'ml, 'mright, 'mf, 'mresult, 'ac, 'at, 'ar, 'ec, 'et, 'eresult) carrier) => fn inject => fn f => (#fnError domain) inject f
end
