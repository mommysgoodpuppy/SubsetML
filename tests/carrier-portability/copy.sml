open CarrierKernel
val copied = {
  fn_ = #fn_ carrier, fnError = #fnError carrier, succeed = #succeed carrier,
  map = #map carrier, map2 = #map2 carrier, andThen = #andThen carrier, mapErr = #mapErr carrier
}
val number: (real, string) result = via copied (fn x => Ok x) (Ok 1.0)
val text: (string, bool) result = via copied (fn x => Ok x) (Ok "text")
