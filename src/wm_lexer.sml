(* Lexical analysis of Workman source, following frontend-v3's lexical design
   (../wm-mini/tooling/frontend-v3/lexical-design.md), for the fragment that corresponds to
   SubsetML. Identifiers may also contain primes, which only SML fallbacks produce. *)
structure WmLexer = struct

  open Syntax

  datatype token =
      WKey of string            (* keyword, punctuation or operator *)
    | WName of string list      (* a dotted path such as Lexer.lex or r.x *)
    | WSelect of string         (* SML fallback `#lab` *)
    | WScon of scon             (* literal; the parser forms negative numbers *)
    | WSml of string            (* an SML fallback declaration, up to its `;` *)
    | WEOF

  datatype 'a step =
      Ok of 'a * real
    | Err of string * pos

  datatype result =
      Tokens of (token * pos) list * comment list
    | LexError of string * pos

  val keywords =
    ["let", "rec", "and", "type", "record", "if", "else", "match", "from", "import", "as",
     "true", "false", "void"]

  (* Longest first, so that a prefix never shadows a longer operator. *)
  val symbols =
    ["..", ".{", "=>", "->", "==", "!=", "<=", ">=", "&&", "||", "++",
     "(", ")", "[", "]", "{", "}", ",", ";", ":", ".", "<", ">", "=", "+", "-", "*", "/", "%",
     "!", "|", "@", "~"]

  val member = fn (x, xs) => SmlList.exists (fn y => y = x) xs

  val isIdentChar = fn c => SubsetChar.isAlphaNum c orelse c = #"_" orelse c = #"'"

  val isSpace = fn c => c = #" " orelse c = #"\t" orelse c = #"\n" orelse c = #"\r" orelse c = #"\f"

  val lex = fn src =>
    case SubsetSource.fromNative src of
      SubsetResult.Err (SubsetString.NonByte offset) => LexError ("source contains a non-byte character", offset)
    | SubsetResult.Ok source =>
    let
      val n = SubsetSource.length source

      val at = fn i => CompilerText.sub (source, i)

      val has = fn (i, c) => i < n andalso at i = c

      val digitAt = fn i => i < n andalso SubsetChar.isDigit (at i)

      val rec skipWhile = fn (p, i) => if i < n andalso p (at i) then skipWhile (p, i + 1.0) else i

      val startsWith = fn (i, s) =>
        i + CompilerText.size s <= n andalso CompilerText.substring (source, i, CompilerText.size s) = s

      (* Whether code precedes offset i on its line. *)
      val trailing = fn i =>
        let
          val rec back = fn k =>
            if k < 0.0 then false
            else
              case at k of
                #"\n" => false
              | c => if isSpace c then back (k - 1.0) else true
        in
          back (i - 1.0)
        end

      (* A nested block comment; i is after the opening `/*`. *)
      val rec blockComment = fn (start, i, depth) =>
        case (Real.== (depth, 0.0), i + 1.0 >= n) of
          (true, _) => Ok ((), i)
        | (false, true) => Err ("unterminated comment", start)
        | (false, false) =>
            case (at i, at (i + 1.0)) of
              (#"/", #"*") => blockComment (start, i + 2.0, depth + 1.0)
            | (#"*", #"/") => blockComment (start, i + 2.0, depth - 1.0)
            | _ => blockComment (start, i + 1.0, depth)

      val hexValue = fn (i, j) =>
        SmlList.foldl (fn (c, acc) => acc * 16.0 + Lexer.digitValue c) 0.0
          (CompilerText.explode (CompilerText.substring (source, i, j - i)))

      val charFromCode = fn (code, pos, next) =>
        case SubsetChar.fromCode code of
          SubsetResult.Ok c => Ok (SOME c, next)
        | SubsetResult.Err error => Err ("SubsetML characters are 8-bit; the code exceeds 255", pos)

      (* An escape; i is just after the backslash. NONE is a gap. *)
      val escape = fn i =>
        if i >= n then Err ("unterminated escape sequence", i - 1.0)
        else
          case at i of
            #"a" => Ok (SOME (#"\007"), i + 1.0)
          | #"b" => Ok (SOME (#"\008"), i + 1.0)
          | #"t" => Ok (SOME #"\t", i + 1.0)
          | #"n" => Ok (SOME #"\n", i + 1.0)
          | #"v" => Ok (SOME #"\v", i + 1.0)
          | #"f" => Ok (SOME #"\f", i + 1.0)
          | #"r" => Ok (SOME #"\r", i + 1.0)
          | #"\"" => Ok (SOME #"\"", i + 1.0)
          | #"'" => Ok (SOME #"'", i + 1.0)
          | #"\\" => Ok (SOME #"\\", i + 1.0)
          | #"^" =>
              if i + 1.0 < n andalso Lexer.byteCode (at (i + 1.0)) >= 64.0 andalso Lexer.byteCode (at (i + 1.0)) <= 95.0
              then charFromCode (Lexer.byteCode (at (i + 1.0)) - 64.0, i - 1.0, i + 2.0)
              else Err ("illegal control escape sequence", i - 1.0)
          | #"u" =>
              if has (i + 1.0, #"{") then
                let val j = skipWhile (SubsetChar.isHexDigit, i + 2.0) in
                  if has (j, #"}") andalso j > i + 2.0 andalso j <= i + 8.0
                  then charFromCode (hexValue (i + 2.0, j), i - 1.0, j + 1.0)
                  else Err ("malformed \\u{...} escape", i - 1.0)
                end
              else
                let val j = skipWhile (SubsetChar.isHexDigit, i + 1.0) in
                  if j - (i + 1.0) >= 4.0 then charFromCode (hexValue (i + 1.0, i + 5.0), i - 1.0, i + 5.0)
                  else Err ("\\u must be followed by four hexadecimal digits", i - 1.0)
                end
          | c =>
              case (SubsetChar.isDigit c, isSpace c) of
                (true, _) =>
                  if digitAt (i + 1.0) andalso digitAt (i + 2.0)
                  then charFromCode (Lexer.digitValue c * 100.0 + Lexer.digitValue (at (i + 1.0)) * 10.0
                                     + Lexer.digitValue (at (i + 2.0)), i - 1.0, i + 3.0)
                  else Err ("decimal escape needs exactly three digits", i - 1.0)
              | (false, true) =>
                  let val j = skipWhile (isSpace, i) in
                    if has (j, #"\\") then Ok (NONE, j + 1.0) else Err ("unterminated string gap", i - 1.0)
                  end
              | (false, false) => Err ("illegal escape sequence", i - 1.0)

      (* A quoted literal body; i is just after the opening quote. *)
      val rec quoted = fn (quote, start, i, acc) =>
        if i >= n then Err ("unterminated literal", start)
        else
          case at i of
            #"\\" =>
              (case escape (i + 1.0) of
                 Ok (NONE, j) => quoted (quote, start, j, acc)
               | Ok (SOME c, j) => quoted (quote, start, j, c :: acc)
               | Err (message, offset) => Err (message, offset))
          | #"\n" => Err ("unterminated literal", start)
          | c =>
              if c = quote then Ok (CompilerText.implode (SmlList.rev acc), i + 1.0)
              else (if Lexer.byteCode c < 32.0 then Err ("control character in a literal", i)
                    else quoted (quote, start, i + 1.0, c :: acc))

      (* A number; SML spells the exponent sign `~` and has no `+`. *)
      val lexNumber = fn start =>
        let
          val text = fn j =>
            CompilerText.translate (fn #"-" => "~" | #"+" => "" | c => CompilerText.str c)
              (CompilerText.substring (source, start, j - start))
          val hexAt = fn j => j < n andalso SubsetChar.isHexDigit (at j)
        in
          case (at start = #"0" andalso has (start + 1.0, #"w"),
                at start = #"0" andalso has (start + 1.0, #"x") andalso hexAt (start + 2.0)) of
            (true, _) => Err ("word constants are not part of SubsetML", start)
          | (false, true) =>
              let val j = skipWhile (SubsetChar.isHexDigit, start + 2.0) in Ok (WScon (SInt (text j)), j) end
          | (false, false) =>
              let
                val j = skipWhile (SubsetChar.isDigit, start)
                val k = if has (j, #".") andalso digitAt (j + 1.0) then skipWhile (SubsetChar.isDigit, j + 1.0) else j
                val signed = if has (k + 1.0, #"-") orelse has (k + 1.0, #"+") then k + 2.0 else k + 1.0
                val m =
                  if (has (k, #"e") orelse has (k, #"E")) andalso digitAt signed
                  then skipWhile (SubsetChar.isDigit, signed)
                  else k
              in
                if Real.== (m, j) then Ok (WScon (SInt (text j)), j) else Ok (WScon (SReal (text m)), m)
              end
        end

      (* A name or dotted path: Lexer.lex, r.x, Syntax.TyCon. *)
      val lexPath = fn start =>
        let
          val rec parts = fn (i, acc) =>
            let
              val j = skipWhile (isIdentChar, i)
              val acc' = CompilerText.substring (source, i, j - i) :: acc
            in
              if has (j, #".") andalso j + 1.0 < n andalso SubsetChar.isAlpha (at (j + 1.0))
              then parts (j + 1.0, acc')
              else (SmlList.rev acc', j)
            end
          val (path, j) = parts (start, [])
        in
          case (path, startsWith (j, ".=="), startsWith (j, ".!=")) of
            (["Real"], true, _) => Ok (WName ["Real", "=="], j + 3.0)
          | (["Real"], _, true) => Ok (WName ["Real", "!="], j + 3.0)
          | ([word], _, _) => if member (word, keywords) then Ok (WKey word, j) else Ok (WName path, j)
          | _ => Ok (WName path, j)
        end

      val lexSymbol = fn i =>
        case SmlList.find (fn s => startsWith (i, s)) symbols of
          SOME s => Ok (WKey s, i + CompilerText.size s)
        | NONE => Err ("unexpected character", i)

      (* SML fallback declarations start a line with one of these words and end at the first
         `;` outside brackets, let ... end, strings and comments. *)
      val smlStart = fn i =>
        let
          val j = skipWhile (isIdentChar, i)
          val word = CompilerText.substring (source, i, j - i)
        in
          (word = "val" orelse word = "datatype" orelse word = "open") andalso not (trailing i)
        end

      val rec skipSmlString = fn i =>
        if i >= n then n
        else
          case at i of
            #"\\" => skipSmlString (i + 2.0)
          | #"\"" => i + 1.0
          | _ => skipSmlString (i + 1.0)

      val rec skipSmlComment = fn (i, depth) =>
        case (Real.== (depth, 0.0), i + 1.0 >= n) of
          (true, _) => i
        | (false, true) => n
        | (false, false) =>
            case (at i, at (i + 1.0)) of
              (#"(", #"*") => skipSmlComment (i + 2.0, depth + 1.0)
            | (#"*", #")") => skipSmlComment (i + 2.0, depth - 1.0)
            | _ => skipSmlComment (i + 1.0, depth)

      val smlPhraseEnd = fn start =>
        let
          val rec go = fn (i, depth) =>
            if i >= n then Err ("unterminated SML declaration (expected `;`)", start)
            else
              case at i of
                #"\"" => go (skipSmlString (i + 1.0), depth)
              | #"#" => if has (i + 1.0, #"\"") then go (skipSmlString (i + 2.0), depth) else go (i + 1.0, depth)
              | #"(" => if has (i + 1.0, #"*") then go (skipSmlComment (i + 2.0, 1.0), depth) else go (i + 1.0, depth + 1.0)
              | #"[" => go (i + 1.0, depth + 1.0)
              | #"{" => go (i + 1.0, depth + 1.0)
              | #")" => go (i + 1.0, depth - 1.0)
              | #"]" => go (i + 1.0, depth - 1.0)
              | #"}" => go (i + 1.0, depth - 1.0)
              | #";" => if Real.== (depth, 0.0) then Ok ((), i) else go (i + 1.0, depth)
              | c =>
                  if SubsetChar.isAlpha c then
                    let val j = skipWhile (isIdentChar, i) in
                      case CompilerText.substring (source, i, j - i) of
                        "let" => go (j, depth + 1.0)
                      | "end" => go (j, depth - 1.0)
                      | _ => go (j, depth)
                    end
                  else go (i + 1.0, depth)
        in
          go (start, 0.0)
        end

      val rec push = fn (r, start, acc, cs) =>
        case r of
          Ok (tok, j) => loop (j, (tok, start) :: acc, cs)
        | Err (message, offset) => LexError (message, offset)

      and comment = fn (start, j, acc, cs) =>
        let
          val body = CompilerText.substring (source, start + 2.0, j - start - 2.0)
        in
          loop (j, acc, (start, body, trailing start) :: cs)
        end

      and loop = fn (i, acc, cs) =>
        if i >= n then Tokens (SmlList.rev ((WEOF, n) :: acc), SmlList.rev cs)
        else
          case (at i, startsWith (i, "//") orelse startsWith (i, "--"), startsWith (i, "/*")) of
            (_, true, _) => comment (i, skipWhile (fn d => d <> #"\n", i), acc, cs)
          | (_, _, true) =>
              (case blockComment (i, i + 2.0, 1.0) of
                 Ok (_, j) => loop (j, acc, (i, CompilerText.substring (source, i + 2.0, j - i - 4.0), trailing i) :: cs)
               | Err (message, offset) => LexError (message, offset))
          | (#"\"", _, _) =>
              (case quoted (#"\"", i, i + 1.0, []) of
                 Ok (s, j) => loop (j, (WScon (SString s), i) :: acc, cs)
               | Err (message, offset) => LexError (message, offset))
          | (#"'", _, _) =>
              (case quoted (#"'", i, i + 1.0, []) of
                 Ok (s, j) =>
                   if Real.== (CompilerText.size s, 1.0) then loop (j, (WScon (SChar ((let val SubsetResult.Ok decoded = SubsetSource.fromNative s in CompilerText.sub (decoded, 0.0) end))), i) :: acc, cs)
                   else LexError ("a character literal must contain exactly one character", i)
               | Err (message, offset) => LexError (message, offset))
          | (#"`", _, _) => LexError ("backtick strings have no SubsetML counterpart", i)
          | (#"#", _, _) =>
              let val j = skipWhile (SubsetChar.isAlphaNum, i + 1.0) in
                if j > i + 1.0 then loop (j, (WSelect (CompilerText.substring (source, i + 1.0, j - i - 1.0)), i) :: acc, cs)
                else LexError ("expected a label after `#`", i)
              end
          | (#"_", _, _) =>
              if i + 1.0 < n andalso isIdentChar (at (i + 1.0))
              then LexError ("identifiers starting with `_` are not SubsetML", i)
              else loop (i + 1.0, (WKey "_", i) :: acc, cs)
          | (c, _, _) =>
              case (isSpace c, SubsetChar.isDigit c, SubsetChar.isAlpha c) of
                (true, _, _) => loop (i + 1.0, acc, cs)
              | (_, true, _) => push (lexNumber i, i, acc, cs)
              | (_, _, true) =>
                  if smlStart i then
                    (case smlPhraseEnd i of
                       Ok (_, j) => loop (j + 1.0, (WSml (CompilerText.substring (source, i, j - i)), i) :: acc, cs)
                     | Err (message, offset) => LexError (message, offset))
                  else push (lexPath i, i, acc, cs)
              | _ => push (lexSymbol i, i, acc, cs)
    in
      loop (0.0, [], [])
    end

end
