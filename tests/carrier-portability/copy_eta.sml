open CarrierKernel
(* Eta expansion makes every field expression a syntactic function value. *)
val copied = {
  fn_ = fn f => fn r => (#fn_ carrier) f r,
  fnError = fn inject => fn f => fn r => (#fnError carrier) inject f r,
  succeed = fn x => (#succeed carrier) x,
  map = fn pair => (#map carrier) pair,
  map2 = fn triple => (#map2 carrier) triple,
  andThen = fn pair => (#andThen carrier) pair,
  mapErr = fn pair => (#mapErr carrier) pair
}
val number: (real, string) result = via copied (fn x => Ok x) (Ok 1.0)
val text: (string, bool) result = via copied (fn x => Ok x) (Ok "text")
val checked = (case number of Ok n => Real.== (n, 1.0) | Err _ => false) andalso text = Ok "text"
val _ = if checked then print "copy_eta: ok\n" else print "copy_eta: FAILED\n"
