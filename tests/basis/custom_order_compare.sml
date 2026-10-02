(* Full-SML IEEE oracle; exceptions are confined to this test harness. *)
val nan = 0.0 / 0.0
val infinity = 1.0 / 0.0
val numbers = [nan, ~infinity, ~2.0, ~0.0, 0.0, 2.0, infinity]
val _ = List.app (fn left => List.app (fn right =>
  let
    val expected =
      if Real.isNan left orelse Real.isNan right then SubsetResult.Err SubsetOrder.Unordered
      else SubsetResult.Ok (case Real.compare (left, right) of
        LESS => SubsetOrder.Less | EQUAL => SubsetOrder.Equal | GREATER => SubsetOrder.Greater)
  in if SubsetOrder.compareReal (left, right) = expected then ()
     else raise Fail "custom real ordering"
  end) numbers) numbers
val _ = print "custom real ordering: IEEE cases ok\n"
