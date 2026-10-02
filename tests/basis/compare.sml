(* Full-SML test harness: refs observe callback order; library sources remain SubsetML. *)
fun assert (name, yes) = if yes then () else (print ("FAIL " ^ name ^ "\n"); OS.Process.exit OS.Process.failure)
fun observed run f xs =
  let val seen = ref []
      fun callback x = (seen := x :: !seen; f x)
      val result = run callback xs
  in (result, List.rev (!seen)) end
val xs = [1, 2, 3, 4]
val inputs = [[], [1], xs]
val _ = List.app (fn ys => (
  assert ("null", SmlList.null ys = List.null ys);
  assert ("rev", SmlList.rev ys = List.rev ys);
  assert ("revAppend", SmlList.revAppend (ys, [5]) = List.revAppend (ys, [5]));
  assert ("map order", observed SmlList.map (fn x => x * 2) ys = observed List.map (fn x => x * 2) ys);
  assert ("mapPartial order", observed SmlList.mapPartial (fn x => if x mod 2 = 0 then SOME x else NONE) ys
    = observed List.mapPartial (fn x => if x mod 2 = 0 then SOME x else NONE) ys);
  assert ("app order", observed SmlList.app (fn _ => ()) ys = observed List.app (fn _ => ()) ys);
  assert ("filter order", observed SmlList.filter (fn x => x mod 2 = 0) ys = observed List.filter (fn x => x mod 2 = 0) ys);
  assert ("partition", SmlList.partition (fn x => x mod 2 = 0) ys = List.partition (fn x => x mod 2 = 0) ys);
  assert ("find short circuit", observed SmlList.find (fn x => x = 2) ys = observed List.find (fn x => x = 2) ys);
  assert ("exists short circuit", observed SmlList.exists (fn x => x = 2) ys = observed List.exists (fn x => x = 2) ys);
  assert ("all short circuit", observed SmlList.all (fn x => x < 3) ys = observed List.all (fn x => x < 3) ys)
)) inputs
fun foldObserved fold ys =
  let val seen = ref []
      val result = fold (fn (x, acc) => (seen := x :: !seen; x - acc)) 0 ys
  in (result, List.rev (!seen)) end
val _ = assert ("foldl", foldObserved SmlList.foldl xs = foldObserved List.foldl xs)
val _ = assert ("foldr", foldObserved SmlList.foldr xs = foldObserved List.foldr xs)
val _ = assert ("concat", SmlList.concat [[], [1, 2], [], [3, 4]] = List.concat [[], [1, 2], [], [3, 4]])
val _ = List.app (fn (a, b) => (
  assert ("zip", SmlListPair.zip (a, b) = ListPair.zip (a, b));
  assert ("unzip", SmlListPair.unzip (SmlListPair.zip (a, b)) = ListPair.unzip (ListPair.zip (a, b)));
  assert ("pair map order", observed (fn f => SmlListPair.map f) (fn (x, y) => x - y) (a, b)
    = observed (fn f => ListPair.map f) (fn (x, y) => x - y) (a, b));
  assert ("pair app order", observed SmlListPair.app (fn _ => ()) (a, b) = observed ListPair.app (fn _ => ()) (a, b));
  assert ("pair all", observed SmlListPair.all (fn (x, y) => x < y) (a, b) = observed ListPair.all (fn (x, y) => x < y) (a, b));
  assert ("pair exists", observed SmlListPair.exists (fn (x, y) => x = y) (a, b) = observed ListPair.exists (fn (x, y) => x = y) (a, b))
)) [([], []), (xs, []), ([], xs), ([1], xs), (xs, [1]), (xs, xs)]
val _ = List.app (fn opt => (
  assert ("getOpt", SmlOption.getOpt (opt, 5) = Option.getOpt (opt, 5));
  assert ("isSome", SmlOption.isSome opt = Option.isSome opt);
  assert ("option map", SmlOption.map (fn x => x + 1) opt = Option.map (fn x => x + 1) opt);
  assert ("option mapPartial", SmlOption.mapPartial (fn x => if x = 1 then NONE else SOME x) opt
    = Option.mapPartial (fn x => if x = 1 then NONE else SOME x) opt)
)) [NONE, SOME 1, SOME 2]
val _ = List.app (fn opt => assert ("join", SmlOption.join opt = Option.join opt)) [NONE, SOME NONE, SOME (SOME 1)]
val _ = List.app (fn x => (
  assert ("option filter", SmlOption.filter (fn x => x > 1) x = Option.filter (fn x => x > 1) x);
  assert ("compose", SmlOption.compose ((fn x => x + 1), (fn x => if x > 1 then SOME x else NONE)) x
    = Option.compose ((fn x => x + 1), (fn x => if x > 1 then SOME x else NONE)) x);
  assert ("composePartial", SmlOption.composePartial ((fn x => if x < 3 then SOME x else NONE), SOME) x
    = Option.composePartial ((fn x => if x < 3 then SOME x else NONE), SOME) x)
)) xs
val _ = print "MLton Basis comparison: ok\n"
