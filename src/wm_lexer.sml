(* @subsetml
from "./syntax.sml" import * as Syntax;
from "./sml_list.sml" import * as SmlList;
from "./subset_char.sml" import * as SubsetChar;
from "./subset_source.sml" import * as SubsetSource;
from "./subset_result.sml" import * as SubsetResult;
from "./subset_string.sml" import * as SubsetString;
from "./compiler_text.sml" import * as CompilerText;
from "./lexer.sml" import * as Lexer;
*)

(* Lexical analysis of Workman source, following frontend-v3's lexical design
   (../wm-mini/tooling/frontend-v3/lexical-design.md), for the fragment that corresponds to
   SubsetML. Identifiers may also contain primes. *)
structure WmLexer = struct

  open Syntax

  datatype token =
      WKey of string            (* keyword, punctuation or operator *)
    | WName of string list      (* a dotted path such as Lexer.lex or r.x *)
    | WSelect of string         (* SML fallback `#lab` *)
    | WScon of scon             (* literal; the parser forms negative numbers *)
    | WOpen of string list list  (* internal resolved header open; never lexed from source *)
    | WEOF

  datatype 'a step =
      Ok of 'a * int
    | Err of string * pos

  datatype result =
      Tokens of (token * pos) list * comment list
    | LexError of string * pos

  val keywords =
    ["let", "rec", "and", "type", "record", "if", "else", "match", "from", "import", "as",
     "true", "false", "void"]

  (* Longest first, so that a prefix never shadows a longer operator. *)
  val symbols =
    ["..", ".{", ":>", "=>", "->", "==", "!=", "<=", ">=", "&&", "||", "++",
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

      val rec skipWhile = fn (p, i) => if i < n andalso p (at i) then skipWhile (p, i + 1) else i

      val startsWith = fn (i, s) =>
        i + CompilerText.size s <= n andalso CompilerText.substring (source, i, CompilerText.size s) = s

      (* Whether code precedes offset i on its line. *)
      val trailing = fn i =>
        let
          val rec back = fn k =>
            if k < 0 then false
            else
              case at k of
                #"\n" => false
              | c => if isSpace c then back (k - 1) else true
        in
          back (i - 1)
        end

      (* A nested block comment; i is after the opening `/*`. *)
      val rec blockComment = fn (start, i, depth) =>
        case ((depth = 0), i + 1 >= n) of
          (true, _) => Ok ((), i)
        | (false, true) => Err ("unterminated comment", start)
        | (false, false) =>
            case (at i, at (i + 1)) of
              (#"/", #"*") => blockComment (start, i + 2, depth + 1)
            | (#"*", #"/") => blockComment (start, i + 2, depth - 1)
            | _ => blockComment (start, i + 1, depth)

      val hexValue = fn (i, j) =>
        SmlList.foldl (fn (c, acc) => acc * 16 + Lexer.digitValue c) 0
          (CompilerText.explode (CompilerText.substring (source, i, j - i)))

      val charFromCode = fn (code, pos, next) =>
        case SubsetChar.fromCode code of
          SubsetResult.Ok c => Ok (SOME c, next)
        | SubsetResult.Err error => Err ("SubsetML characters are 8-bit; the code exceeds 255", pos)

      (* An escape; i is just after the backslash. NONE is a gap. *)
      val escape = fn i =>
        if i >= n then Err ("unterminated escape sequence", i - 1)
        else
          case at i of
            #"a" => Ok (SOME (#"\007"), i + 1)
          | #"b" => Ok (SOME (#"\008"), i + 1)
          | #"t" => Ok (SOME #"\t", i + 1)
          | #"n" => Ok (SOME #"\n", i + 1)
          | #"v" => Ok (SOME #"\v", i + 1)
          | #"f" => Ok (SOME #"\f", i + 1)
          | #"r" => Ok (SOME #"\r", i + 1)
          | #"\"" => Ok (SOME #"\"", i + 1)
          | #"'" => Ok (SOME #"'", i + 1)
          | #"\\" => Ok (SOME #"\\", i + 1)
          | #"^" =>
              if i + 1 < n andalso Lexer.byteCode (at (i + 1)) >= 64 andalso Lexer.byteCode (at (i + 1)) <= 95
              then charFromCode (Lexer.byteCode (at (i + 1)) - 64, i - 1, i + 2)
              else Err ("illegal control escape sequence", i - 1)
          | #"u" =>
              if has (i + 1, #"{") then
                let val j = skipWhile (SubsetChar.isHexDigit, i + 2) in
                  if has (j, #"}") andalso j > i + 2 andalso j <= i + 8
                  then charFromCode (hexValue (i + 2, j), i - 1, j + 1)
                  else Err ("malformed \\u{...} escape", i - 1)
                end
              else
                let val j = skipWhile (SubsetChar.isHexDigit, i + 1) in
                  if j - (i + 1) >= 4 then charFromCode (hexValue (i + 1, i + 5), i - 1, i + 5)
                  else Err ("\\u must be followed by four hexadecimal digits", i - 1)
                end
          | c =>
              case (SubsetChar.isDigit c, isSpace c) of
                (true, _) =>
                  if digitAt (i + 1) andalso digitAt (i + 2)
                  then charFromCode (Lexer.digitValue c * 100 + Lexer.digitValue (at (i + 1)) * 10
                                     + Lexer.digitValue (at (i + 2)), i - 1, i + 3)
                  else Err ("decimal escape needs exactly three digits", i - 1)
              | (false, true) =>
                  let val j = skipWhile (isSpace, i) in
                    if has (j, #"\\") then Ok (NONE, j + 1) else Err ("unterminated string gap", i - 1)
                  end
              | (false, false) => Err ("illegal escape sequence", i - 1)

      (* A quoted literal body; i is just after the opening quote. *)
      val rec quoted = fn (quote, start, i, acc) =>
        if i >= n then Err ("unterminated literal", start)
        else
          case at i of
            #"\\" =>
              (case escape (i + 1) of
                 Ok (NONE, j) => quoted (quote, start, j, acc)
               | Ok (SOME c, j) => quoted (quote, start, j, c :: acc)
               | Err (message, offset) => Err (message, offset))
          | #"\n" => Err ("unterminated literal", start)
          | c =>
              if c = quote then Ok (CompilerText.implode (SmlList.rev acc), i + 1)
              else (if Lexer.byteCode c < 32 then Err ("control character in a literal", i)
                    else quoted (quote, start, i + 1, c :: acc))

      (* A number; SML spells the exponent sign `~` and has no `+`. *)
      val lexNumber = fn start =>
        let
          val text = fn j =>
            CompilerText.translate (fn #"-" => "~" | #"+" => "" | c => CompilerText.str c)
              (CompilerText.substring (source, start, j - start))
          val hexAt = fn j => j < n andalso SubsetChar.isHexDigit (at j)
        in
          case (at start = #"0" andalso has (start + 1, #"w"),
                at start = #"0" andalso has (start + 1, #"x") andalso hexAt (start + 2)) of
            (true, _) => Err ("word constants are not part of SubsetML", start)
          | (false, true) =>
              let val j = skipWhile (SubsetChar.isHexDigit, start + 2) in Ok (WScon (SInt (text j)), j) end
          | (false, false) =>
              let
                val j = skipWhile (SubsetChar.isDigit, start)
                val k = if has (j, #".") andalso digitAt (j + 1) then skipWhile (SubsetChar.isDigit, j + 1) else j
                val signed = if has (k + 1, #"-") orelse has (k + 1, #"+") then k + 2 else k + 1
                val m =
                  if (has (k, #"e") orelse has (k, #"E")) andalso digitAt signed
                  then skipWhile (SubsetChar.isDigit, signed)
                  else k
              in
                if (m = j) then Ok (WScon (SInt (text j)), j) else Ok (WScon (SReal (text m)), m)
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
              if has (j, #".") andalso j + 1 < n andalso SubsetChar.isAlpha (at (j + 1))
              then parts (j + 1, acc')
              else (SmlList.rev acc', j)
            end
          val (path, j) = parts (start, [])
        in
          case (path, startsWith (j, ".=="), startsWith (j, ".!=")) of
            (["Real"], true, _) => Ok (WName ["Real", "=="], j + 3)
          | (["Real"], _, true) => Ok (WName ["Real", "!="], j + 3)
          | ([word], _, _) => if member (word, keywords) then Ok (WKey word, j) else Ok (WName path, j)
          | _ => Ok (WName path, j)
        end

      val lexSymbol = fn i =>
        case SmlList.find (fn s => startsWith (i, s)) symbols of
          SOME s => Ok (WKey s, i + CompilerText.size s)
        | NONE => Err ("unexpected character", i)

      val rec loop = fn (i, acc, cs) =>
        if i >= n then Tokens (SmlList.rev ((WEOF, n) :: acc), SmlList.rev cs)
        else
          case (at i, startsWith (i, "//") orelse startsWith (i, "--"), startsWith (i, "/*")) of
            (_, true, _) => let
              val j = skipWhile (fn d => d <> #"\n", i)
              val body = CompilerText.substring (source, i + 2, j - i - 2)
            in
              loop (j, acc, (i, body, trailing i) :: cs)
            end
          | (_, _, true) =>
              (case blockComment (i, i + 2, 1) of
                 Ok (_, j) => loop (j, acc, (i, CompilerText.substring (source, i + 2, j - i - 4), trailing i) :: cs)
               | Err (message, offset) => LexError (message, offset))
          | (#"\"", _, _) =>
              (case quoted (#"\"", i, i + 1, []) of
                 Ok (s, j) => loop (j, (WScon (SString s), i) :: acc, cs)
               | Err (message, offset) => LexError (message, offset))
          | (#"'", _, _) =>
              (case quoted (#"'", i, i + 1, []) of
                 Ok (s, j) =>
                   if (CompilerText.size s = 1) then loop (j, (WScon (SChar ((let val SubsetResult.Ok decoded = SubsetSource.fromNative s in CompilerText.sub (decoded, 0) end))), i) :: acc, cs)
                   else LexError ("a character literal must contain exactly one character", i)
               | Err (message, offset) => LexError (message, offset))
          | (#"`", _, _) => LexError ("backtick strings have no SubsetML counterpart", i)
          | (#"#", _, _) =>
              let val j = skipWhile (SubsetChar.isAlphaNum, i + 1) in
                if j > i + 1 then loop (j, (WSelect (CompilerText.substring (source, i + 1, j - i - 1)), i) :: acc, cs)
                else LexError ("expected a label after `#`", i)
              end
          | (#"_", _, _) =>
              if i + 1 < n andalso isIdentChar (at (i + 1))
              then LexError ("identifiers starting with `_` are not SubsetML", i)
              else loop (i + 1, (WKey "_", i) :: acc, cs)
          | (c, _, _) =>
              case (isSpace c, SubsetChar.isDigit c, SubsetChar.isAlpha c) of
                (true, _, _) => loop (i + 1, acc, cs)
              | (_, true, _) => (case lexNumber i of
                     Ok (tok, j) => loop (j, (tok, i) :: acc, cs)
                   | Err (message, offset) => LexError (message, offset))
              | (_, _, true) =>
                  (case lexPath i of
                     Ok (tok, j) => loop (j, (tok, i) :: acc, cs)
                   | Err (message, offset) => LexError (message, offset))
              | _ => (case lexSymbol i of
                     Ok (tok, j) => loop (j, (tok, i) :: acc, cs)
                   | Err (message, offset) => LexError (message, offset))
    in
      loop (0, [], [])
    end

end
