(* Generated ordering runs with MLton and Workman, including IEEE edge cases. *)
structure CustomOrderPortable = struct
  val nan = 0.0 / 0.0
  val infinity = 1.0 / 0.0
  val values = [~infinity, ~2.0, ~0.0, 0.0, 2.0, infinity]
  val ordered = SubsetList.all (values, fn left => SubsetList.all (values, fn right =>
    case SubsetOrder.compareReal (left, right) of
      SubsetResult.Err error => false
    | SubsetResult.Ok order =>
        SubsetOrder.compareReal (right, left) = SubsetResult.Ok (SubsetOrder.reverse order)))
  val unordered = SubsetList.all (nan :: values, fn value =>
    SubsetOrder.compareReal (nan, value) = SubsetResult.Err SubsetOrder.Unordered
    andalso SubsetOrder.compareReal (value, nan) = SubsetResult.Err SubsetOrder.Unordered)
  val checked = ordered andalso unordered
    andalso SubsetOrder.compareReal (~2.0, 2.0) = SubsetResult.Ok SubsetOrder.Less
    andalso SubsetOrder.compareReal (2.0, ~2.0) = SubsetResult.Ok SubsetOrder.Greater
    andalso SubsetOrder.compareReal (~0.0, 0.0) = SubsetResult.Ok SubsetOrder.Equal
    andalso SubsetOrder.compareReal (infinity, infinity) = SubsetResult.Ok SubsetOrder.Equal
    andalso SubsetOrder.compareReal (~infinity, infinity) = SubsetResult.Ok SubsetOrder.Less
    andalso SubsetChar.contains ([#"a", #"b"], #"b")
    andalso not (SubsetChar.contains ([], #"a"))
    andalso not (SubsetChar.contains ([#"a"], #"b"))
  val _ = if checked then print "custom ordering: ok\n" else print "FAILED\n"
end
