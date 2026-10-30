open SubsetOptionValue
(* Full-SML observation harness; the library itself remains within SubsetML. *)
fun assert (label, condition) = if condition then () else (print ("FAIL " ^ label ^ "\n"); OS.Process.exit OS.Process.failure)
fun observe run xs =
  let val log = ref []
      val answer = run (xs, fn x => (log := x :: !log; x < 3))
  in (answer, List.rev (!log)) end
val _ = assert ("exists short circuit", observe SubsetList.exists [1, 2, 3] = (true, [1]))
val _ = assert ("all short circuit", observe SubsetList.all [1, 2, 3, 4] = (false, [1, 2, 3]))
val _ = assert ("find short circuit", observe SubsetList.find [1, 2, 3] = (SOME 1, [1]))
val _ = assert ("filter order", observe SubsetList.filter [1, 2, 3] = ([1, 2], [1, 2, 3]))
val _ = assert ("partition order", observe SubsetList.partition [1, 2, 3] = (([1, 2], [3]), [1, 2, 3]))
val seen = ref []
fun record x = (seen := x :: !seen; x)
val _ = assert ("map result", SubsetList.map ([1, 2, 3], record) = [1, 2, 3])
val _ = assert ("map order", List.rev (!seen) = [1, 2, 3])
val _ = seen := []
val _ = assert ("traverse error", SubsetList.traverse ([1, 2, 3], fn x =>
  (record x; if x = 2 then SubsetResult.Err x else SubsetResult.Ok x)) = SubsetResult.Err 2)
val _ = assert ("traverse stops", List.rev (!seen) = [1, 2])
val _ = seen := []
val _ = assert ("zip checks both lengths", SubsetListPair.zip ([1], [2, 3]) = SubsetResult.Err SubsetListPair.UnequalLengths)
val _ = assert ("pair traversal length error", SubsetListPair.traverse ([1], [2, 3], fn (x, y) =>
  (record x; SubsetResult.Ok y)) = SubsetResult.Err SubsetListPair.LengthMismatch)
val _ = assert ("no callback before length failure", !seen = [])
val _ = assert ("map skips error callback", SubsetResult.map (SubsetResult.Err 1, fn x =>
  (record x; x)) = SubsetResult.Err 1)
val _ = assert ("option skips absent callback", SubsetOption.map (NONE, fn x =>
  (record x; x)) = NONE)
val _ = assert ("no skipped callbacks", !seen = [])
val _ = assert ("preserve callback error", SubsetListPair.traverse ([1, 2], [3, 4], fn (x, y) =>
  if x = 2 then SubsetResult.Err "user error" else SubsetResult.Ok y)
  = SubsetResult.Err (SubsetListPair.CallbackError "user error"))
val _ = print "custom Basis callbacks: ok\n"
