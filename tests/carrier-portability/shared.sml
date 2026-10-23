open CarrierKernel
val number: (real, string) result = via carrier (fn x => Ok (x + 1.0)) (Ok 1.0)
val text: (string, bool) result = via carrier (fn x => Ok (x ^ "!")) (Ok "hi")
val mapped: (bool, string) result = (#map carrier) (Ok "value", fn _ => true)
val combined: (string, bool) result = (#map2 carrier) (Ok "a", Ok "b", fn (a, b) => a ^ b)
val checked = mapped = Ok true andalso combined = Ok "ab" andalso (case number of Ok n => Real.== (n, 2.0) | Err _ => false)
  andalso text = Ok "hi!"
val _ = if checked then print "shared: ok\n" else print "shared: FAILED\n"
