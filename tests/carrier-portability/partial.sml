open CarrierKernel
val viaResult = via carrier
val number: (real, string) result = viaResult (fn x => Ok x) (Ok 1.0)
val text: (string, bool) result = viaResult (fn x => Ok x) (Ok "text")
