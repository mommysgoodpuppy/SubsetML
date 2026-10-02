(* Canonical literal spellings and printer precedence, shared across native and WM execution. *)
structure SmlPrinter = struct
  val escaped = fn (result, expected) =>
    case result of SubsetResult.Err error => false | SubsetResult.Ok text => text = expected
  val render = fn document => Doc.render ("", [], fn lines => lines, document)
  val spellings =
    case SubsetListPair.zip (SubsetChar.byteChars, SmlEscapeExpected.spellings) of
      SubsetResult.Err error => false
    | SubsetResult.Ok pairs => SubsetList.all (pairs, fn (byte, expected) =>
        escaped (SubsetSmlEscape.escapeByte byte, expected)
        andalso SmlPrint.scon (Syntax.SChar byte) = "#\"" ^ expected ^ "\""
        andalso Print.scon (Syntax.SChar byte) = SmlPrint.scon (Syntax.SChar byte)
        andalso (case Lexer.lex (SmlPrint.scon (Syntax.SChar byte)) of
          Lexer.Tokens ([(Lexer.TScon (Syntax.SChar actual), ignoredFirstPos), (Lexer.TEOF, ignoredLastPos)], []) => actual = byte
        | Lexer.Tokens (tokens, comments) => false | Lexer.LexError (message, offset) => false))
  val strings =
    case SubsetString.toNative SubsetChar.byteChars of
      SubsetResult.Err error => false
    | SubsetResult.Ok value =>
        escaped (SubsetSmlEscape.escapeString value, SmlEscapeExpected.all)
        andalso escaped (SubsetSmlEscape.escapeBytes SubsetChar.byteChars, SmlEscapeExpected.all)
        andalso SmlPrint.scon (Syntax.SString value) = "\"" ^ SmlEscapeExpected.all ^ "\""
        andalso Print.scon (Syntax.SString value) = SmlPrint.scon (Syntax.SString value)
        andalso (case Lexer.lex (SmlPrint.scon (Syntax.SString value)) of
          Lexer.Tokens ([(Lexer.TScon (Syntax.SString actual), ignoredFirstPos), (Lexer.TEOF, ignoredLastPos)], []) => actual = value
        | Lexer.Tokens (tokens, comments) => false | Lexer.LexError (message, offset) => false)
        andalso escaped (SubsetSmlEscape.escapeBytes [], "")
        andalso escaped (SubsetSmlEscape.escapeString "", "")
  val format = fn input =>
    case Parser.parse input of
      Parser.ParseError (message, offset) => NONE
    | Parser.Program (program, comments) => SOME (Doc.render (input, comments, SmlPrint.commentStyle,
        Doc.stack (SubsetList.map (program, SmlPrint.topdec))))
  val formatting = format "val x = 1.0 + 2.0 * 3.0" = SOME "val x = 1.0 + 2.0 * 3.0\n"
    andalso format "val x = if c then a else (if d then b else e)"
      = SOME "val x = if c then a else (if d then b else e)\n"
    andalso render (SmlPrint.dec (Syntax.DOpen (0.0, [["A", "B"], ["C"]]))) = "open A.B C\n"
    andalso render (SmlPrint.ty (Syntax.TyArrow (Syntax.TyTuple [Syntax.TyCon ([], ([], "real")),
      Syntax.TyCon ([], ([], "real"))], Syntax.TyCon ([], ([], "bool"))))) = "real * real -> bool\n"
    andalso SmlPrint.commentStyle [] = ["(**)"]
    andalso SmlPrint.commentStyle [" a "] = ["(* a *)"]
    andalso SmlPrint.commentStyle ["a", "b", "c"] = ["(*a", "b", "c*)"]
  val _ = if spellings andalso strings andalso formatting then print "portable SML printer: ok\n" else print "FAILED\n"
end
