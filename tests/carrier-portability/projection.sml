open CarrierKernel
val extracted = #fn_ carrier
val number: (real, string) result = extracted (fn x => Ok x) (Ok 1.0)
val text: (string, bool) result = extracted (fn x => Ok x) (Ok "text")
