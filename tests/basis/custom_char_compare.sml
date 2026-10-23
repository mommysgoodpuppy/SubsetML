(* Full-SML oracle harness, intentionally outside the SubsetML library. *)
val classifiers = [
  (SubsetChar.isLower, Char.isLower), (SubsetChar.isUpper, Char.isUpper),
  (SubsetChar.isDigit, Char.isDigit), (SubsetChar.isGraph, Char.isGraph),
  (SubsetChar.isPrint, Char.isPrint), (SubsetChar.isCntrl, Char.isCntrl),
  (SubsetChar.isAscii, Char.isAscii), (SubsetChar.isAlpha, Char.isAlpha),
  (SubsetChar.isAlphaNum, Char.isAlphaNum), (SubsetChar.isHexDigit, Char.isHexDigit),
  (SubsetChar.isSpace, Char.isSpace), (SubsetChar.isPunct, Char.isPunct)]
val chars = List.tabulate (256, Char.chr)
val _ = List.app (fn c => (
  if (case SubsetChar.toCode c of SubsetResult.Ok code => code = Char.ord c | SubsetResult.Err error => false)
     andalso SubsetChar.fromCode (Char.ord c) = SubsetResult.Ok c
  then () else raise Fail "custom character code conversion";
  List.app (fn (actual, oracle) =>
    if actual c = oracle c then () else raise Fail "custom character classification") classifiers;
  if SubsetChar.toLower c = Char.toLower c andalso SubsetChar.toUpper c = Char.toUpper c
  then () else raise Fail "custom character casing";
  List.app (fn d =>
    let val expected = case Char.compare (c, d) of
      LESS => SubsetOrder.Less | EQUAL => SubsetOrder.Equal | GREATER => SubsetOrder.Greater
    in
      if Char.ord c < 128 andalso Char.ord d < 128 then
        if SubsetChar.compareAscii (c, d) = SubsetResult.Ok expected then () else raise Fail "custom ASCII ordering"
      else if SubsetChar.compareAscii (c, d) = SubsetResult.Err SubsetChar.NonAscii then ()
      else raise Fail "non-ASCII comparison should fail"
    end) chars
)) chars
val _ = if SubsetOrder.reverse SubsetOrder.Greater = SubsetOrder.Less then ()
        else raise Fail "reverse ordering"
val _ = print "custom characters: all 256 values and 65536 pairs ok\n"
val invalidCodes = [~1, 256, 2147483647]
val _ = List.app (fn code => if SubsetChar.fromCode code = SubsetResult.Err SubsetChar.InvalidCode
  then () else raise Fail "invalid character code accepted") invalidCodes
