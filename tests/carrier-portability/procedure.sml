open CarrierKernel
datatype error = ParseFailure of string | DomainFailure of string
val procedure = fn input =>
  let
    val parse = viaError carrier ParseFailure
      (fn text => if text = "12" then Ok 12.0 else Err "bad input")
    val validate = viaError carrier DomainFailure
      (fn number => if number > 0.0 then Ok number else Err "not positive")
    val render = via carrier (fn _ => Ok "compiled")
  in render (validate (parse (Ok input))) end
val skipped: (string, error) result = via carrier
  (fn _ => (print "FAILED: stage ran\n"; Ok "wrong")) (Err (ParseFailure "stop"))
val other: (bool, bool) result = viaError carrier (fn e => not e) (fn _ => Err false) (Ok ())
val checked = procedure "12" = Ok "compiled"
  andalso procedure "bad" = Err (ParseFailure "bad input")
  andalso skipped = Err (ParseFailure "stop") andalso other = Err true
val _ = if checked then print "procedure: ok\n" else print "procedure: FAILED\n"
