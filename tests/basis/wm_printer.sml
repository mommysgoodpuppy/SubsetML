(* Workman literal bytes and printer formatting, shared across native and WM execution. *)
structure WmPrinter = struct
  val render = fn document => Doc.render ("", [], fn lines => lines, document)
  val characters =
    case SubsetListPair.zip (SubsetChar.byteChars, WmEscapeExpected.characters) of
      SubsetResult.Err error => false
    | SubsetResult.Ok pairs => SubsetList.all (pairs, fn (byte, expected) =>
        WmPrint.scon (Syntax.SChar byte) = "'" ^ expected ^ "'"
        andalso (case WmLexer.lex (WmPrint.scon (Syntax.SChar byte)) of
          WmLexer.Tokens ([(WmLexer.WScon (Syntax.SChar actual), _), (WmLexer.WEOF, _)], []) => actual = byte
        | WmLexer.Tokens (tokens, comments) => false | WmLexer.LexError (message, offset) => false))
  val strings =
    case SubsetString.toNative SubsetChar.byteChars of
      SubsetResult.Err error => false
    | SubsetResult.Ok value =>
        WmPrint.scon (Syntax.SString value) = "\"" ^ WmEscapeExpected.string ^ "\""
        andalso (case WmLexer.lex (WmPrint.scon (Syntax.SString value)) of
          WmLexer.Tokens ([(WmLexer.WScon (Syntax.SString actual), _), (WmLexer.WEOF, _)], []) => actual = value
        | WmLexer.Tokens (tokens, comments) => false | WmLexer.LexError (message, offset) => false)
  val names = WmPrint.capitalize "" = "" andalso WmPrint.capitalize "name" = "Name"
    andalso WmPrint.capitalize "_name" = "_name"
    andalso WmPrint.dotted (["A", "B"], "x") = "A.B.x"
    andalso WmPrint.tyVarName "'value" = "value"
    andalso WmPrint.fileName "WmPrint" = "wm_print.wm"
    andalso WmPrint.fileName "XML" = "x_m_l.wm"
    andalso WmPrint.valueName (["Num", "String"], "size") = "String.size"
    andalso WmPrint.isConName ([], "Thing") andalso not (WmPrint.isConName ([], "value"))
  val formatting = WmPrint.scon (Syntax.SReal "~1") = "-1"
    andalso WmPrint.scon (Syntax.SReal "~1.5E~2") = "-1.5E-2"
    andalso WmPrint.scon (Syntax.SReal "1.0E2") = "1.0E2"
    andalso WmPrint.commentStyle [" a "] = ["// a"]
    andalso WmPrint.commentStyle [] = []
    andalso WmPrint.commentStyle ["a", "b", "c"] = ["/*a", "b", "c*/"]
    andalso render (WmPrint.topdec (["A"], Syntax.TopDecs [Syntax.SDec (Syntax.DOpen (0, [["A"]]))]))
      = "from \"./a.wm\" import *;\n"
    andalso render (WmPrint.topdec ([], Syntax.TopExp (0,
      Syntax.EApp (Syntax.EId (0, ([], "+")), Syntax.ETuple [Syntax.EScon (0, Syntax.SReal "1"),
        Syntax.EScon (0, Syntax.SReal "2")])))) = "1 + 2;\n"
  val _ = if characters andalso strings andalso names andalso formatting
    then print "portable Workman printer: ok\n" else print "FAILED\n"
end
