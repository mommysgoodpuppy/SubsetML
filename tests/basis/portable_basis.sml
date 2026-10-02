(* Executed unchanged through MLton and through the generated Workman module graph. *)
structure PortableBasis = struct
  val names = ["a", "b", "c"]
  val yes = SmlList.exists (fn x => x = "b") names
    andalso SmlList.all (fn x => x <> "d") names
    andalso SmlList.map (fn x => x ^ "!") names = ["a!", "b!", "c!"]
    andalso SmlList.filter (fn x => x <> "b") names = ["a", "c"]
    andalso SmlList.concat [["a"], [], ["b", "c"]] = names
    andalso SmlList.rev names = ["c", "b", "a"]
    andalso SmlListPair.zip (["a", "b"], [true]) = [("a", true)]
    andalso SmlListPair.all (fn (x, y) => x = y) (["a"], ["a", "b"])
    andalso SmlOption.map (fn x => x ^ "!") (SOME "a") = SOME "a!"
    andalso SmlOption.getOpt (NONE, "fallback") = "fallback"
    andalso Real.== (SmlList.foldl (fn (x, acc) => x - acc) 0.0 [1.0, 2.0, 3.0], 2.0)
  val _ = if yes then print "portable basis: ok\n" else print "portable basis: FAILED\n"
end
