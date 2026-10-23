open CarrierKernel
(* A record parameter's fn_ field has one monotype throughout this invocation. *)
val both = fn {fn_ = invoke, fnError, succeed, map, map2, andThen, mapErr} =>
  (invoke (fn x => Ok (x + 1.0)) (Ok 1.0),
   invoke (fn x => Ok (x ^ "!")) (Ok "hi"))
