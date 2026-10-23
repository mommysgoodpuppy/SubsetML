open CarrierKernel
val viaResult = fn f => fn result => via carrier f result
val number: (real, string) result = viaResult (fn x => Ok (x + 1.0)) (Ok 1.0)
val text: (string, bool) result = viaResult (fn x => Ok (x ^ "!")) (Ok "hi")
val mapped: (bool, string) result = (#map carrier) (Ok "value", fn _ => true)
val combined: (string, bool) result = (#map2 carrier) (Ok "a", Ok "b", fn (a, b) => a ^ b)
val checked = mapped = Ok true andalso combined = Ok "ab" andalso (case number of Ok n => Real.== (n, 2.0) | Err _ => false) andalso text = Ok "hi!"
val _ = if checked then print "eta: ok\n" else print "eta: FAILED\n"
