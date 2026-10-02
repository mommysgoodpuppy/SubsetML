(* Shared lexer execution, covering cached byte input and decoded high-byte literals. *)
structure LexerBytes = struct
  val sml =
    case Lexer.lex "val x = \"\\000\\255\"" of
      Lexer.Tokens ([(Lexer.TKey "val", a), (Lexer.TId "x", b), (Lexer.TKey "=", c),
        (Lexer.TScon (Syntax.SString text), d), (Lexer.TEOF, e)], []) =>
          text = "\000\255" andalso Real.== (a, 0.0) andalso Real.== (b, 4.0)
          andalso Real.== (c, 6.0) andalso Real.== (d, 8.0) andalso Real.== (e, 18.0)
    | Lexer.Tokens (tokens, comments) => false | Lexer.LexError (message, pos) => false
  val workman =
    case WmLexer.lex "let x = '\\u00ff';" of
      WmLexer.Tokens ([(WmLexer.WKey "let", a), (WmLexer.WName ["x"], b), (WmLexer.WKey "=", c),
        (WmLexer.WScon (Syntax.SChar ch), d), (WmLexer.WKey ";", e), (WmLexer.WEOF, f)], []) =>
          ch = #"\255" andalso Real.== (a, 0.0) andalso Real.== (b, 4.0)
          andalso Real.== (c, 6.0) andalso Real.== (d, 8.0) andalso Real.== (e, 16.0)
          andalso Real.== (f, 17.0)
    | WmLexer.Tokens (tokens, comments) => false | WmLexer.LexError (message, pos) => false
  val escapes =
    case Lexer.lex "#\"\\^A\" #\"\\a\"" of
      Lexer.Tokens ([(Lexer.TScon (Syntax.SChar first), a), (Lexer.TScon (Syntax.SChar second), b),
        (Lexer.TEOF, c)], []) => first = #"\001" andalso second = #"\007"
    | Lexer.Tokens (tokens, comments) => false | Lexer.LexError (message, pos) => false
  val invalid =
    (case Lexer.lex "\"\\u0100\"" of Lexer.LexError (message, pos) => Real.== (pos, 1.0)
      | Lexer.Tokens (tokens, comments) => false)
    andalso (case WmLexer.lex "'ab'" of WmLexer.LexError (message, pos) => Real.== (pos, 0.0)
      | WmLexer.Tokens (tokens, comments) => false)
  val parsing =
    (case Parser.parse "val x = 1.0 + 2.0 * 3.0" of
       Parser.Program ([Syntax.TopDecs [Syntax.SDec (Syntax.DVal (pos, [], plain, []))]], []) =>
         not (SubsetList.isEmpty plain)
     | Parser.Program (program, comments) => false | Parser.ParseError (message, offset) => false)
    andalso Real.== (Parser.precedence "+", 6.0)
    andalso Real.== (Parser.precedence "unknown", ~1.0)
    andalso Parser.rightAssoc "::" andalso not (Parser.rightAssoc "+")
    andalso Parser.describe (Lexer.TLong (["A", "B"], "c")) = "identifier `A.B.c`"
  val failures =
    (case Parser.bind (Parser.Fail ("preserved", 42.0))
       (fn value => fn tokens => Parser.Done (false, tokens)) of
       Parser.Fail (message, offset) => message = "preserved" andalso Real.== (offset, 42.0)
     | Parser.Done (value, tokens) => false)
    andalso (case Parser.parse "val x =" of
       Parser.ParseError (message, offset) => Real.== (offset, 7.0)
     | Parser.Program (program, comments) => false)
    andalso (case Parser.parse "\"\\u0100\"" of
       Parser.ParseError (message, offset) => Real.== (offset, 1.0)
     | Parser.Program (program, comments) => false)
    andalso (case Parser.parse "structure A = struct end structure B = struct end" of
       Parser.ParseError (message, offset) => Real.== (offset, 25.0)
     | Parser.Program (program, comments) => false)
  val strings = SubsetString.concat [] = ""
    andalso SubsetString.concat ["a", "", "b", "c", "d"] = "abcd"
    andalso SubsetString.concatWith ([], ".") = ""
    andalso SubsetString.concatWith (["a"], ".") = "a"
    andalso SubsetString.concatWith (["", "a", "", "b", ""], ".") = ".a..b."
    andalso SubsetString.concatWith (["\000", "\255"], "") = "\000\255"
  val _ = if sml andalso workman andalso escapes andalso invalid andalso parsing andalso failures andalso strings then print "byte lexers and parser: ok\n"
    else print "FAILED\n"
end
