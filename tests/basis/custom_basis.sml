(* The custom library executes through both MLton and generated Workman. *)
structure CustomBasis = struct

  val names = ["a", "b", "c"]
  val resultOk = SubsetResult.map (SubsetResult.Ok "a", fn x => x ^ "!") = SubsetResult.Ok "a!"
    andalso SubsetResult.mapError (SubsetResult.Err "bad", fn x => x ^ "!") = SubsetResult.Err "bad!"
    andalso SubsetResult.andThen (SubsetResult.Ok "a", fn x => SubsetResult.Ok (x ^ "!")) = SubsetResult.Ok "a!"
    andalso SubsetResult.via (fn x => SubsetResult.Ok (x ^ "!")) (SubsetResult.Ok "a") = SubsetResult.Ok "a!"
    andalso SubsetResult.viaError SOME (fn x => SubsetResult.Err x) (SubsetResult.Ok "bad") = SubsetResult.Err (SOME "bad")
    andalso SubsetResult.viaError
      (fn error => (print "UNEXPECTED ERROR MAPPER\n"; SOME error))
      (fn value => (print "UNEXPECTED RESULT STAGE\n"; SubsetResult.Ok value))
      (SubsetResult.Err (SOME "earlier")) = SubsetResult.Err (SOME "earlier")
    andalso SubsetResult.getOr (SubsetResult.Err "bad", "fallback") = "fallback"
    andalso SubsetResult.isOk (SubsetResult.Ok true)
    andalso SubsetResult.toOption (SubsetResult.Err "bad") = NONE
  val optionOk = SubsetOption.map (SOME "a", fn x => x ^ "!") = SOME "a!"
    andalso SubsetOption.andThen (NONE, fn x => SOME x) = (NONE : string option)
    andalso SubsetOption.filter (SOME "a", fn x => x = "b") = NONE
    andalso SubsetOption.getOr (NONE, "fallback") = "fallback"
    andalso SubsetOption.toResult (NONE, "absent") = (SubsetResult.Err "absent" : (string, string) SubsetResult.result)
  val listOk = SubsetList.isEmpty []
    andalso SubsetList.reverseAppend (["b", "a"], ["c"]) = names
    andalso SubsetList.append (["a"], ["b", "c"]) = names
    andalso SubsetList.concat [["a"], [], ["b", "c"]] = names
    andalso SubsetList.map (names, fn x => x ^ "!") = ["a!", "b!", "c!"]
    andalso SubsetList.filterMap (names, fn x => if x = "b" then NONE else SOME x) = ["a", "c"]
    andalso SubsetList.partition (names, fn x => x = "b") = (["b"], ["a", "c"])
    andalso SubsetList.filter (names, fn x => x <> "b") = ["a", "c"]
    andalso SubsetList.find (names, fn x => x = "b") = SOME "b"
    andalso SubsetList.exists (names, fn x => x = "b")
    andalso SubsetList.all (names, fn x => x <> "d")
    andalso SubsetList.foldLeft (names, "", fn (x, acc) => acc ^ x) = "abc"
    andalso SubsetList.foldRight (names, "", fn (x, acc) => acc ^ x) = "cba"
    andalso SubsetList.head names = SubsetResult.Ok "a"
    andalso SubsetList.tail names = SubsetResult.Ok ["b", "c"]
    andalso SubsetList.last names = SubsetResult.Ok "c"
    andalso SubsetList.head ([] : string list) = SubsetResult.Err SubsetList.EmptyList
    andalso SubsetList.tail ([] : string list) = SubsetResult.Err SubsetList.EmptyList
    andalso SubsetList.last ([] : string list) = SubsetResult.Err SubsetList.EmptyList
  val pairOk = SubsetListPair.zip (names, [true]) = SubsetResult.Err SubsetListPair.UnequalLengths
    andalso SubsetListPair.zip ([], [true]) = (SubsetResult.Err SubsetListPair.UnequalLengths :
      ((string * bool) list, SubsetListPair.error) SubsetResult.result)
    andalso SubsetListPair.zip (names, names) = SubsetResult.Ok [("a", "a"), ("b", "b"), ("c", "c")]
    andalso SubsetListPair.unzip [("a", true), ("b", false)] = (["a", "b"], [true, false])
    andalso SubsetListPair.map (names, names, fn (a, b) => a ^ b) = SubsetResult.Ok ["aa", "bb", "cc"]
  val _ = SubsetList.forEach (names, fn x => print ("visit " ^ x ^ "\n"))
  val stopped = SubsetList.traverse (["a", "stop", "unvisited"], fn x =>
    (print ("try " ^ x ^ "\n"); if x = "stop" then SubsetResult.Err "stopped" else SubsetResult.Ok x))
  val unmapped = SubsetListPair.map (names, ["a"], fn (a, b) =>
    (print "UNEXPECTED CALLBACK\n"; a ^ b))
  val pairStopped = SubsetListPair.traverse (["a", "stop", "unvisited"], [true, true, true], fn (x, y) =>
    if x = "stop" then SubsetResult.Err "stopped" else SubsetResult.Ok x)
  val charOk = SubsetChar.compareAscii (#"a", #"b") = SubsetResult.Ok SubsetOrder.Less
    andalso SubsetChar.compareAscii (#"b", #"a") = SubsetResult.Ok SubsetOrder.Greater
    andalso SubsetChar.compareAscii (#"a", #"a") = SubsetResult.Ok SubsetOrder.Equal
    andalso SubsetOrder.reverse SubsetOrder.Less = SubsetOrder.Greater
    andalso SubsetOrder.reverse SubsetOrder.Equal = SubsetOrder.Equal
    andalso SubsetChar.toLower #"Z" = #"z"
    andalso SubsetChar.toUpper #"a" = #"A"
    andalso SubsetChar.toUpper #"!" = #"!"
    andalso SubsetChar.toLower #"\255" = #"\255"
    andalso SubsetChar.isSpace #"\t"
    andalso not (SubsetChar.isSpace #"\000")
    andalso SubsetChar.isHexDigit #"F"
    andalso not (SubsetChar.isHexDigit #"G")
  val nonAscii = SubsetChar.compareAscii (#"\255", #"a") = SubsetResult.Err SubsetChar.NonAscii
  val checked = nonAscii andalso charOk andalso resultOk andalso optionOk andalso listOk andalso pairOk
    andalso stopped = SubsetResult.Err "stopped"
    andalso unmapped = SubsetResult.Err SubsetListPair.UnequalLengths
    andalso pairStopped = SubsetResult.Err (SubsetListPair.CallbackError "stopped")
  val _ = if checked then print "custom basis: ok\n" else print "custom basis: FAILED\n"

end
