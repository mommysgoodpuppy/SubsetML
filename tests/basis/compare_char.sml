(* Full-SML reference harness; test every character in SubsetML's 8-bit character domain. *)
fun assert (name, yes) = if yes then () else (print ("FAIL " ^ name ^ "\n"); OS.Process.exit OS.Process.failure)
val chars = List.tabulate (256, Char.chr)
val classifiers =
  [("isLower", SmlChar.isLower, Char.isLower), ("isUpper", SmlChar.isUpper, Char.isUpper),
   ("isDigit", SmlChar.isDigit, Char.isDigit), ("isGraph", SmlChar.isGraph, Char.isGraph),
   ("isPrint", SmlChar.isPrint, Char.isPrint), ("isCntrl", SmlChar.isCntrl, Char.isCntrl),
   ("isAscii", SmlChar.isAscii, Char.isAscii), ("isAlpha", SmlChar.isAlpha, Char.isAlpha),
   ("isAlphaNum", SmlChar.isAlphaNum, Char.isAlphaNum), ("isHexDigit", SmlChar.isHexDigit, Char.isHexDigit),
   ("isSpace", SmlChar.isSpace, Char.isSpace), ("isPunct", SmlChar.isPunct, Char.isPunct)]
val _ = List.app (fn (name, ours, basis) =>
  List.app (fn c => assert (name ^ " " ^ Int.toString (Char.ord c), ours c = basis c)) chars) classifiers
val _ = List.app (fn c => (
  assert ("toLower", SmlChar.toLower c = Char.toLower c);
  assert ("toUpper", SmlChar.toUpper c = Char.toUpper c);
  List.app (fn d => assert ("compare", SmlChar.compare (c, d) = Char.compare (c, d))) chars
)) chars
val strings = ["", "a", "aaa", "aAzZ09! \t\r\n", "\000\127\128\255", String.implode chars]
val _ = List.app (fn s =>
  let val ours = SmlChar.contains s val basis = Char.contains s
      val oursNot = SmlChar.notContains s val basisNot = Char.notContains s
  in List.app (fn c => (
    assert ("contains", ours c = basis c);
    assert ("notContains", oursNot c = basisNot c)
  )) chars end) strings
val _ = print "MLton Char comparison (256 characters): ok\n"
