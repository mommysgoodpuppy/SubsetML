(* Exact layout and portable byte helpers, executed natively and in Workman. *)
structure DocPortable = struct
  val layout = Doc.render ("", [], fn lines => lines,
    Doc.group ("[", ",", "]", [Doc.text "a", Doc.text "b"])) = "[a, b]\n"
    andalso Doc.render ("", [], fn lines => lines,
      Doc.indent (2.0, Doc.stack [Doc.text "a", Doc.text "b"])) = "  a\n  b\n"
    andalso Doc.trim " \t\r\n\011\012a\000\255 \t" = "a\000\255"
    andalso Doc.trim " \t " = "" andalso Doc.trim "" = ""
    andalso Doc.spaces 0.0 = "" andalso Doc.spaces 3.0 = "   "
  val positions =
    let val source = CompilerText.source "a\n  \nb" in
      Real.== (Doc.lineStart (source, 0.0), 0.0)
      andalso Real.== (Doc.lineStart (source, 1.0), 0.0)
      andalso Real.== (Doc.lineStart (source, 2.0), 2.0)
      andalso Real.== (Doc.lineStart (source, 99.0), 5.0)
      andalso Doc.blankLineBefore (source, 5.0)
      andalso not (Doc.blankLineBefore (source, 0.0))
    end
  val comments = Doc.render ("a\n\nb", [], fn lines => lines,
      Doc.stack [Doc.atom (0.0, "a"), Doc.atom (3.0, "b")]) = "a\n\nb\n"
    andalso Doc.render ("  a\n", [(0.0, "header", false), (3.0, "tail", true)],
      fn lines => SubsetList.map (lines, fn text => "#" ^ text), Doc.atom (2.0, "a"))
      = "#header\n\na #tail\n"
    andalso Doc.commentLines (CompilerText.source "  a", (2.0, "first\n    second\n \n", false),
      fn lines => lines) = ["first", "  second", "", ""]
  val fields = SubsetBytes.fields ([], fn c => c = #",") = [[]]
    andalso SubsetBytes.fields ([#",", #"a", #",", #",", #"b", #","], fn c => c = #",")
      = [[], [#"a"], [], [#"b"], []]
    andalso SubsetBytes.trim ([#" ", #"a", #" ", #"b", #"\t"], SubsetChar.isSpace)
      = [#"a", #" ", #"b"]
  val counts = SubsetList.repeat (#"x", ~0.0) = SubsetResult.Ok []
    andalso SubsetList.repeat (#"x", 3.0) = SubsetResult.Ok [#"x", #"x", #"x"]
    andalso (case SubsetList.repeat (#"x", 128.0) of
      SubsetResult.Ok bytes => Real.== (SubsetList.length bytes, 128.0) andalso SubsetList.all (bytes, fn c => c = #"x")
    | SubsetResult.Err error => false)
    andalso SubsetList.all ([~1.0, 0.5, 128.5, 4503599627370495.5, 9007199254740992.0, 0.0 / 0.0, 1.0 / 0.0],
      fn count => SubsetList.repeat (#"x", count) = SubsetResult.Err SubsetList.InvalidCount)
    andalso SubsetList.dropWhile (["x", "stop", "late"], fn text =>
      if text = "x" then true else (if text = "stop" then false else (print "BAD\n"; true))) = ["stop", "late"]
  val _ = if layout andalso positions andalso comments andalso fields andalso counts
    then print "portable document layout: ok\n" else print "FAILED\n"
end
