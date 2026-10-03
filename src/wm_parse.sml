(* @subsetml
from "./syntax.sml" import * as Syntax;
from "./wm_lexer.sml" import * as WmLexer;
from "./subset_string.sml" import * as SubsetString;
from "./sml_list.sml" import * as SmlList;
from "./compiler_text.sml" import * as CompilerText;
from "./subset_char.sml" import * as SubsetChar;
from "./wm_print.sml" import * as WmPrint;
from "./subset_list.sml" import * as SubsetList;
from "./parser.sml" import * as Parser;
from "./sml_option.sml" import * as SmlOption;
*)

(* Parsing Workman source into SubsetML abstract syntax: the reverse of WmPrint.

   It accepts the Workman fragment that corresponds to SubsetML, plus the SML fallbacks that
   WmPrint emits (`div`, `mod`, `@`, `o`, `before`, `#lab`, `~`). Workman features outside
   SubsetML (pinned match names, `%`, pipes, JSON, FFI imports, ...) are reported as errors. *)
structure WmParse = struct

  open Syntax
  open WmLexer

  type toks = (token * pos) list

  datatype 'a res =
      Done of 'a * toks
    | Fail of string * pos

  val bind = fn r => fn k =>
    case r of
      Done (x, ts) => k x ts
    | Fail (message, pos) => Fail (message, pos)

  val peek = fn
      t :: _ => t
    | [] => (WEOF, 0.0)

  val advance = fn
      _ :: rest => rest
    | [] => []

  val posOf = fn ts => let val (_, p) = peek ts in p end

  val isKey = fn (k, ts) =>
    case peek ts of
      (WKey k', _) => k = k'
    | _ => false

  val describe = fn
      WKey k => "`" ^ k ^ "`"
    | WName path => "`" ^ SubsetString.concatWith (path, ".") ^ "`"
    | WSelect l => "`#" ^ l ^ "`"
    | WScon _ => "a literal"
    | WSml _ => "an SML declaration"
    | WEOF => "end of input"

  val expected = fn (what, ts) =>
    let val (t, p) = peek ts in Fail ("expected " ^ what ^ ", found " ^ describe t, p) end

  val expect = fn (k, ts) =>
    if isKey (k, ts) then Done ((), advance ts) else expected ("`" ^ k ^ "`", ts)

  (* `item (sep item)*`, allowing a trailing separator before `close`. *)
  val separated = fn (item, sep, close, ts) =>
    let
      val rec loop = fn (acc, ts) =>
        if isKey (close, ts) then Done (SmlList.rev acc, ts)
        else
          case item ts of
            Done (x, rest) =>
              if isKey (sep, rest) then loop (x :: acc, advance rest)
              else Done (SmlList.rev (x :: acc), rest)
          | Fail (message, offset) => Fail (message, offset)
    in
      loop ([], ts)
    end

  (* `open items close` *)
  val delimited = fn (openK, item, sep, close, ts) =>
    bind (expect (openK, ts)) (fn _ => fn ts =>
      bind (separated (item, sep, close, ts)) (fn xs => fn ts =>
        bind (expect (close, ts)) (fn _ => fn ts => Done (xs, ts))))

  (* --------------------------------------------------------------------------------------- *)
  (* Names (the inverse of WmPrint's) *)

  val isUpperName = fn s => CompilerText.firstIs (s, SubsetChar.isUpper)

  val decapitalize = fn s =>
    case CompilerText.characters s of [] => "" | c :: rest => CompilerText.stringOf (SubsetChar.toLower c :: rest)

  val valueName = fn
      ([], "None") => ([], "NONE")
    | ([], "Some") => ([], "SOME")
    | id =>
        (case SmlList.find (fn (_, wm) => wm = id) WmPrint.numNames of
           SOME entry => let val (sml, _) = entry in sml end
         | NONE => id)

  val tyConName = fn
      ([], "Void") => ([], "unit")
    | ([], "Number") => ([], "real")
    | (qs, s) => (qs, decapitalize s)

  (* Splits a path into structure qualifiers, the named value, and record field selections. *)
  val splitPath = fn path =>
    let
      val rec go = fn
          (quals, [last]) => (SmlList.rev quals, last, [])
        | (quals, c :: rest) => if isUpperName c then go (c :: quals, rest) else (SmlList.rev quals, c, rest)
        | (quals, []) => (SmlList.rev quals, "", [])
    in
      go ([], path)
    end

  val pathExp = fn (p, path) =>
    let val (quals, base, fields) = splitPath path in
      SmlList.foldl (fn (l, e) => EApp (ESelect (p, l), e)) (EId (p, valueName (quals, base))) fields
    end

  (* "./sml_print.wm" names the structure SmlPrint. *)
  val structureName = fn file =>
    let
      val base =
        case SmlList.rev (CompilerText.fields (file, fn c => c = #"/")) of
          last :: _ => last
        | [] => file
      val stem = if CompilerText.isSuffix (base, ".wm") then CompilerText.slice (base, 0.0, CompilerText.size base - 3.0) else base
    in
      SubsetString.concat (SmlList.map WmPrint.capitalize
                       (SmlList.filter (fn w => w <> "") (CompilerText.fields (stem, fn c => c = #"_"))))
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Types *)

  val rec parseType = fn ts =>
    bind (parseTypeAtom ts) (fn t => fn ts =>
      if isKey ("->", ts) then
        bind (parseType (advance ts)) (fn r => fn ts => Done (TyArrow (t, r), ts))
      else Done (t, ts))

  and parseTypeAtom = fn ts =>
    case peek ts of
      (WKey "(", _) =>
        bind (delimited ("(", parseType, ",", ")", ts)) (fn types => fn ts =>
          case types of
            [single] => Done (single, ts)
          | [] => expected ("a type", ts)
          | _ => Done (TyTuple types, ts))
    | (WName [v], _) =>
        if isUpperName v then typeName ([], v, advance ts) else Done (TyVar ("'" ^ v), advance ts)
    | (WName path, _) =>
        (case SmlList.rev path of
           last :: rest => typeName (SmlList.rev rest, last, advance ts)
         | [] => expected ("a type", ts))
    | _ => expected ("a type", ts)

  and typeName = fn (quals, name, ts) =>
    if isKey ("<", ts) then
      bind (delimited ("<", parseType, ",", ">", ts)) (fn args => fn ts =>
        Done (TyCon (args, tyConName (quals, name)), ts))
    else Done (TyCon ([], tyConName (quals, name)), ts)

  (* --------------------------------------------------------------------------------------- *)
  (* Patterns. As in WmPrint, `inMatch` marks a match arm and `binds` whether a bare name binds
     at this position. *)

  val number = fn c =>
    case c of
      SInt s => SReal (s ^ ".0")
    | _ => c

  val negativeLiteral = fn (minusPos, ts) =>
    case peek ts of
      (WScon (SInt s), p) => if Real.== (p, minusPos + 1.0) then SOME (SReal ("~" ^ s ^ ".0")) else NONE
    | (WScon (SReal s), p) => if Real.== (p, minusPos + 1.0) then SOME (SReal ("~" ^ s)) else NONE
    | _ => NONE

  (* Builds `h1 :: ... :: tail`. *)
  val consPat = fn (p, items, tail) =>
    SmlList.foldr (fn (h, t) => PApp (p, ([], "::"), PTuple [h, t])) tail items

  (* `[a, b, ..tail]` after the `[`: the items and the optional spread tail. *)
  val listItems = fn (item, ts) =>
    let
      val rec go = fn (acc, ts) =>
        case peek ts of
          (WKey "]", _) => Done ((SmlList.rev acc, NONE), advance ts)
        | (WKey "..", _) =>
            bind (item (advance ts)) (fn t => fn ts =>
              bind (expect ("]", if isKey (",", ts) then advance ts else ts)) (fn _ => fn ts =>
                Done ((SmlList.rev acc, SOME t), ts)))
        | _ =>
            (case item ts of
               Done (x, rest) =>
                 if isKey (",", rest) then go (x :: acc, advance rest)
                 else bind (expect ("]", rest)) (fn _ => fn rest => Done ((SmlList.rev (x :: acc), NONE), rest))
             | Fail (message, offset) => Fail (message, offset))
    in
      go ([], ts)
    end

  val rec parsePat = fn (inMatch, binds, ts) =>
    let val child = fn b => fn ts => parseAnnotated (inMatch, b orelse not inMatch, ts) in
      case peek ts of
        (WKey "_", _) => Done (PWild, advance ts)
      | (WKey "void", _) => Done (PTuple [], advance ts)
      | (WKey "true", p) => Done (PId (p, ([], "true")), advance ts)
      | (WKey "false", p) => Done (PId (p, ([], "false")), advance ts)
      | (WScon (SInt _), p) => Fail ("real constants may not occur in patterns", p)
      | (WScon (SReal _), p) => Fail ("real constants may not occur in patterns", p)
      | (WScon c, p) => Done (PScon (p, c), advance ts)
      | (WKey "-", p) =>
          (case negativeLiteral (p, advance ts) of
             SOME (SInt s) => Done (PScon (p, SInt s), advance (advance ts))
           | _ => expected ("a pattern", ts))
      | (WKey ".{", p) =>
          let
            val field = fn ts =>
              case peek ts of
                (WName [l], lp) =>
                  if isKey ("=", advance ts) then
                    bind (child false (advance (advance ts))) (fn q => fn ts => Done ((l, q), ts))
                  else Done ((l, PId (lp, ([], l))), advance ts)
              | _ => expected ("a record field", ts)
          in
            bind (separated (field, ",", "}", advance ts)) (fn fields => fn ts =>
              bind (expect ("}", ts)) (fn _ => fn ts => Done (PRecord (p, fields), ts)))
          end
      | (WKey "[", p) =>
          bind (listItems (child true, advance ts)) (fn (items, tail) => fn ts =>
            case tail of
              NONE => Done (PList items, ts)
            | SOME t => Done (consPat (p, items, t), ts))
      | (WKey "(", _) =>
          bind (delimited ("(", child false, ",", ")", ts)) (fn ps => fn ts =>
            case ps of
              [single] => Done (single, ts)
            | _ => Done (PTuple ps, ts))
      | (WName ["Var"], _) =>
          (case (peek (advance ts), peek (advance (advance ts)), peek (advance (advance (advance ts)))) of
             ((WKey "(", _), (WName [x], p), (WKey ")", _)) =>
               Done (PId (p, ([], x)), advance (advance (advance (advance ts))))
           | _ => expected ("`Var(name)`", ts))
      | (WName path, p) =>
          let
            val name :: reversedQuals = SubsetList.reverse path
            val quals = SubsetList.reverse reversedQuals
          in
            case (isUpperName name, binds, SmlList.null quals) of
              (true, _, _) =>
                if isKey ("(", advance ts) then
                  bind (delimited ("(", child true, ",", ")", advance ts)) (fn args => fn ts =>
                    case args of
                      [single] => Done (PApp (p, valueName (quals, name), single), ts)
                    | _ => Done (PApp (p, valueName (quals, name), PTuple args), ts))
                else Done (PId (p, valueName (quals, name)), advance ts)
            | (false, true, true) => Done (PId (p, ([], name)), advance ts)
            | (false, _, _) =>
                Fail ("`" ^ SubsetString.concatWith (path, ".") ^ "` here is a pinned value in Workman, "
                      ^ "which SubsetML patterns cannot express; write Var(" ^ name ^ ") to bind", p)
          end
      | _ => expected ("a pattern", ts)
    end

  (* A pattern that may carry a type annotation, as inside parentheses. *)
  and parseAnnotated = fn (inMatch, binds, ts) =>
    bind (parsePat (inMatch, binds, ts)) (fn p => fn ts =>
      if isKey (":", ts) then
        bind (parseType (advance ts)) (fn t => fn ts => Done (PTyped (p, t), ts))
      else Done (p, ts))

  (* --------------------------------------------------------------------------------------- *)
  (* Expressions *)

  (* Whether the `(` at the head of ts begins a lambda, i.e. its matching `)` is followed by `=>`. *)
  val lambdaAhead = fn ts =>
    let
      val rec scan = fn (depth, ts) =>
        case peek ts of
          (WEOF, _) => false
        | (WKey k, _) =>
            if k = "(" orelse k = "[" orelse k = "{" orelse k = ".{" then scan (depth + 1.0, advance ts)
            else
              (if k = ")" orelse k = "]" orelse k = "}" then
                 (if Real.== (depth, 1.0) then isKey ("=>", advance ts) else scan (depth - 1.0, advance ts))
               else scan (depth, advance ts))
        | _ => scan (depth, advance ts)
    in
      isKey ("(", ts) andalso scan (0.0, ts)
    end

  val binLevel = fn
      "||" => SOME 1.0
    | "&&" => SOME 2.0
    | "==" => SOME 3.0
    | "!=" => SOME 3.0
    | "<" => SOME 4.0
    | ">" => SOME 4.0
    | "<=" => SOME 4.0
    | ">=" => SOME 4.0
    | "++" => SOME 5.0
    | "+" => SOME 5.0
    | "-" => SOME 5.0
    | "*" => SOME 6.0
    | "/" => SOME 6.0
    | "%" => SOME 6.0
    | _ => NONE

  val smlOperator = fn
      "==" => "="
    | "!=" => "<>"
    | "++" => "^"
    | s => s

  (* The SML operators WmPrint keeps where Workman has none. *)
  val fallbackOperator = fn ts =>
    case peek ts of
      (WKey "@", _) => SOME "@"
    | (WName [s], _) => if s = "div" orelse s = "mod" orelse s = "o" orelse s = "before" then SOME s else NONE
    | _ => NONE

  val infixApp = fn (opr, p, l, r) => EApp (EId (p, ([], opr)), ETuple [l, r])

  val consExp = fn (p, items, tail) =>
    SmlList.foldr (fn (h, t) => infixApp ("::", p, h, t)) tail items

  val startsDecl = fn ts =>
    isKey ("let", ts) orelse isKey ("type", ts) orelse isKey ("record", ts)
    orelse (case peek ts of (WSml _, _) => true | _ => false)

  datatype item =
      IDec of dec
    | IExp of exp

  (* A block's items as an expression: declarations become `let`, a trailing `;` gives (). *)
  val rec blockExp = fn (items, terminated) =>
    let
      val rec decs = fn
          (IDec d :: rest, acc) => decs (rest, d :: acc)
        | (rest, acc) => (SmlList.rev acc, rest)
      val rec exps = fn
          (IExp e :: rest, acc) => exps (rest, e :: acc)
        | (rest, acc) => (SmlList.rev acc, rest)
      val (ds, rest) = decs (items, [])
      val (es, after) = exps (rest, [])
      val body =
        case (after, terminated) of
          ([], true) => es @ [ETuple []]
        | ([], false) => es
        | (_, _) => es @ [blockExp (after, terminated)]
    in
      case (ds, body) of
        ([], [single]) => single
        | _ => ELet (ds, body)
    end

  val rec parseExp = fn ts =>
    case peek ts of
      (WKey "if", _) =>
        bind (expect ("(", advance ts)) (fn _ => fn ts =>
          bind (parseExp ts) (fn c => fn ts =>
            bind (expect (")", ts)) (fn _ => fn ts =>
              bind (parseBlock ts) (fn a => fn ts =>
                bind (expect ("else", ts)) (fn _ => fn ts =>
                  bind (parseBlock ts) (fn b => fn ts => Done (EIf (c, a, b), ts)))))))
    | (WKey "match", _) =>
        if isKey ("{", advance ts) then
          bind (parseArms (advance ts)) (fn rules => fn ts => Done (EFn rules, ts))
        else
          (if lambdaAhead (advance ts) then parseMatchFunction (advance ts)
           else
             bind (delimited ("(", parseExp, ",", ")", advance ts)) (fn values => fn ts =>
               bind (parseArms ts) (fn rules => fn ts =>
                 case values of
                   [single] => Done (ECase (single, rules), ts)
                 | _ => Done (ECase (ETuple values, rules), ts))))
    | (WKey "(", _) => if lambdaAhead ts then parseLambda ts else parseFallback ts
    | _ => parseFallback ts

  (* `match(x, y) => { arms }`: a function of its named parameters. *)
  and parseMatchFunction = fn ts =>
    let
      val name = fn ts =>
        case peek ts of
          (WName [x], p) => Done ((p, x), advance ts)
        | _ => expected ("a parameter name", ts)
    in
      bind (delimited ("(", name, ",", ")", ts)) (fn names => fn ts =>
        bind (expect ("=>", ts)) (fn _ => fn ts =>
          bind (parseArms ts) (fn rules => fn ts =>
            let
              val param =
                case names of
                  [(p, x)] => PId (p, ([], x))
                | _ => PTuple (SmlList.map (fn (p, x) => PId (p, ([], x))) names)
              val value =
                case names of
                  [(p, x)] => EId (p, ([], x))
                | _ => ETuple (SmlList.map (fn (p, x) => EId (p, ([], x))) names)
            in
              Done (EFn [(param, ECase (value, rules))], ts)
            end)))
    end

  (* `(params) => body`, where the body is a block or another lambda. *)
  and parseLambda = fn ts =>
    let
      val param = fn ts =>
        bind (parsePat (false, true, ts)) (fn p => fn ts =>
          if isKey (":", ts) then bind (parseType (advance ts)) (fn t => fn ts => Done (PTyped (p, t), ts))
          else Done (p, ts))
    in
      bind (delimited ("(", param, ",", ")", ts)) (fn ps => fn ts =>
        bind (expect ("=>", ts)) (fn _ => fn ts =>
          bind (if lambdaAhead ts then parseLambda ts else parseBlock ts) (fn body => fn ts =>
            let
              val p =
                case ps of
                  [single] => single
                | _ => PTuple ps
            in
              Done (EFn [(p, body)], ts)
            end)))
    end

  and parseArms = fn ts =>
    let
      val arm = fn ts =>
        bind (parseAnnotated (true, false, ts)) (fn p => fn ts =>
          bind (expect ("=>", ts)) (fn _ => fn ts =>
            bind (parseBlock ts) (fn e => fn ts => Done ((p, e), ts))))
    in
      delimited ("{", arm, ",", "}", ts)
    end

  and parseBlock = fn ts =>
    let
      val rec items = fn (acc, ts) =>
        case peek ts of
          (WKey "}", _) => Done ((SmlList.rev acc, true), advance ts)
        | _ =>
            if startsDecl ts then
              bind (parseDecl ts) (fn ds => fn ts => items (SmlList.map IDec ds @ acc, ts))
            else
              bind (parseExp ts) (fn e => fn ts =>
                if isKey (";", ts) then items (IExp e :: acc, advance ts)
                else bind (expect ("}", ts)) (fn _ => fn ts => Done ((SmlList.rev (IExp e :: acc), false), ts)))
    in
      bind (expect ("{", ts)) (fn _ => fn ts =>
        bind (items ([], ts)) (fn (parts, terminated) => fn ts =>
          (* An empty block or one ending in `;` yields void. *)
          Done (blockExp (parts, terminated orelse SmlList.null parts), ts)))
    end

  (* The SML operators kept by WmPrint bind loosest. *)
  and parseFallback = fn ts =>
    let
      val rec more = fn (l, ts) =>
        case fallbackOperator ts of
          SOME opr =>
            bind (parseBinary (1.0, advance ts)) (fn r => fn ts' => more (infixApp (opr, posOf ts, l, r), ts'))
        | NONE => Done (l, ts)
    in
      bind (parseBinary (1.0, ts)) (fn l => fn ts => more (l, ts))
    end

  and parseBinary = fn (minLevel, ts) =>
    let
      val rec more = fn (l, ts) =>
        case peek ts of
          (WKey opr, p) =>
            (case binLevel opr of
               SOME level =>
                 if level < minLevel then Done (l, ts)
                 else
                   (if opr = "%" then Fail ("`%` has no SubsetML counterpart (SML `mod` differs)", p)
                    else
                      bind (parseBinary (level + 1.0, advance ts)) (fn r => fn ts =>
                        more (case opr of
                                "&&" => ECase (ETuple [l, r],
                                  [(PTuple [PId (p, ([], "true")), PId (p, ([], "true"))], EId (p, ([], "true"))),
                                   (PWild, EId (p, ([], "false")))])
                              | "||" => ECase (ETuple [l, r],
                                  [(PTuple [PId (p, ([], "false")), PId (p, ([], "false"))], EId (p, ([], "false"))),
                                   (PWild, EId (p, ([], "true")))])
                              | _ =>
                                  case (opr, l) of
                                    ("==", ETyped (x, TyCon ([], ([], "real")))) =>
                                      EApp (EId (p, (["Real"], "==")), ETuple [x, r])
                                  | ("!=", ETyped (x, TyCon ([], ([], "real")))) =>
                                      EApp (EId (p, (["Real"], "!=")), ETuple [x, r])
                                  | _ => infixApp (smlOperator opr, p, l, r), ts)))
             | NONE => Done (l, ts))
        | _ => Done (l, ts)
    in
      bind (parseUnary ts) (fn l => fn ts => more (l, ts))
    end

  and parseUnary = fn ts =>
    case peek ts of
      (WKey "!", p) => bind (parseUnary (advance ts)) (fn e => fn ts => Done (EApp (EId (p, ([], "not")), e), ts))
    | (WKey "-", p) =>
        (case negativeLiteral (p, advance ts) of
           SOME c => Done (EScon (p, c), advance (advance ts))
         | NONE => bind (parseUnary (advance ts)) (fn e => fn ts => Done (EApp (EId (p, ([], "~")), e), ts)))
    | _ => parsePostfix ts

  (* A primary expression followed by calls. *)
  and parsePostfix = fn ts =>
    let
      val rec calls = fn (f, ts) =>
        if isKey ("(", ts) andalso not (lambdaAhead ts) then
          bind (delimited ("(", parseExp, ",", ")", ts)) (fn args => fn ts =>
            case (f, args) of
              (* WmPrint's spelling of SML `@`; the SML Basis has no List.append. *)
              (EId (p, (["List"], "append")), [l, r]) => calls (infixApp ("@", p, l, r), ts)
            | (_, [single]) => calls (EApp (f, single), ts)
            | _ => calls (EApp (f, ETuple args), ts))
        else Done (f, ts)
    in
      bind (parsePrimary ts) (fn e => fn ts => calls (e, ts))
    end

  and parsePrimary = fn ts =>
    case peek ts of
      (WScon c, p) => Done (EScon (p, number c), advance ts)
    | (WKey "true", p) => Done (EId (p, ([], "true")), advance ts)
    | (WKey "false", p) => Done (EId (p, ([], "false")), advance ts)
    | (WKey "void", _) => Done (ETuple [], advance ts)
    | (WKey "~", p) => Done (EId (p, ([], "~")), advance ts)
    | (WName path, p) => Done (pathExp (p, path), advance ts)
    | (WSelect l, p) =>
        if CompilerText.firstIs (l, SubsetChar.isDigit)
        then Fail ("tuple selectors are not part of SubsetML; use a pattern such as (_, x)", p)
        else Done (ESelect (p, l), advance ts)
    | (WKey "[", p) =>
        bind (listItems (parseExp, advance ts)) (fn (items, tail) => fn ts =>
          case tail of
            NONE => Done (EList items, ts)
          | SOME t => Done (consExp (p, items, t), ts))
    | (WKey ".{", p) =>
        let
          val field = fn ts =>
            case peek ts of
              (WName [l], lp) =>
                if isKey ("=", advance ts) then
                  bind (parseExp (advance (advance ts))) (fn e => fn ts => Done ((l, e), ts))
                else Done ((l, EId (lp, ([], l))), advance ts)
            | _ => expected ("a record field", ts)
        in
          bind (separated (field, ",", "}", advance ts)) (fn fields => fn ts =>
            bind (expect ("}", ts)) (fn _ => fn ts => Done (ERecord (p, fields), ts)))
        end
    | (WKey "{", _) => parseBlock ts
    | (WKey "(", _) =>
        bind (parseExp (advance ts)) (fn first => fn ts =>
          case peek ts of
            (WKey ":", _) =>
              bind (parseType (advance ts)) (fn t => fn ts =>
                bind (expect (")", ts)) (fn _ => fn ts => Done (ETyped (first, t), ts)))
          | (WKey ",", _) =>
              bind (separated (parseExp, ",", ")", advance ts)) (fn rest => fn ts =>
                bind (expect (")", ts)) (fn _ => fn ts => Done (ETuple (first :: rest), ts)))
          | (WKey ";", _) =>
              bind (separated (parseExp, ";", ")", advance ts)) (fn rest => fn ts =>
                bind (expect (")", ts)) (fn _ => fn ts => Done (ESeq (first :: rest), ts)))
          | _ => bind (expect (")", ts)) (fn _ => fn ts => Done (first, ts)))
    | (WKey "if", _) => parseExp ts
    | (WKey "match", _) => parseExp ts
    | _ => expected ("an expression", ts)

  (* --------------------------------------------------------------------------------------- *)
  (* Declarations. A namespace import (`import * as X`) yields no declaration: SML refers to
     structures by name without importing them. *)

  and parseDecl = fn ts =>
    let val p = posOf ts in
      case peek ts of
        (WSml text, _) =>
          (case Parser.parse text of
             Parser.Program (prog, _) =>
               Done (SmlList.concat (SmlList.map (fn
                         TopDecs sds => SmlList.concat (SmlList.map (fn SDec d => [d] | SStructure (_, _) => []) sds)
                       | TopExp (_, _) => []) prog), advance ts)
           | Parser.ParseError (msg, q) => Fail ("in an SML declaration: " ^ msg, p + q))
      | (WKey "let", _) =>
          let
            val isRec = isKey ("rec", advance ts)
            val binding = fn ts =>
              bind (parsePat (false, true, ts)) (fn pat => fn ts =>
                let
                  val rhs = fn (pat, ts) =>
                    bind (expect ("=", ts)) (fn _ => fn ts =>
                      bind (parseExp ts) (fn e => fn ts => Done ((pat, e), ts)))
                in
                  if isKey (":", ts) then
                    bind (parseType (advance ts)) (fn t => fn ts => rhs (PTyped (pat, t), ts))
                  else rhs (pat, ts)
                end)
            val rec bindings = fn ts =>
              bind (binding ts) (fn b => fn ts =>
                if isKey ("and", ts) then
                  bind (bindings (advance ts)) (fn bs => fn ts => Done (b :: bs, ts))
                else Done ([b], ts))
          in
            bind (bindings (if isRec then advance (advance ts) else advance ts)) (fn bs => fn ts =>
              bind (expect (";", ts)) (fn _ => fn ts =>
                if isRec then
                  (if SmlList.all (fn (_, e) => case e of EFn _ => true | _ => false) bs
                   then Done ([DVal (p, [], [], bs)], ts)
                   else Fail ("the right side of a `let rec` binding must be a function", p))
                else Done ([DVal (p, [], bs, [])], ts)))
          end
      | (WKey "type", _) => parseTypeDecl (p, advance ts)
      | (WKey "record", _) =>
          (case peek (advance ts) of
             (WName [name], _) =>
               bind (typeParams (advance (advance ts))) (fn vs => fn ts =>
                 bind (expect ("=", ts)) (fn _ => fn ts =>
                   let
                     val field = fn ts =>
                       case peek ts of
                         (WName [l], _) =>
                           bind (expect (":", advance ts)) (fn _ => fn ts =>
                             bind (parseType ts) (fn t => fn ts => Done ((l, t), ts)))
                       | _ => expected ("a record field", ts)
                   in
                     bind (delimited ("{", field, ",", "}", ts)) (fn fields => fn ts =>
                       bind (expect (";", ts)) (fn _ => fn ts =>
                         Done ([DType (p, [(vs, decapitalize name, TyRecord fields)])], ts)))
                   end))
           | _ => expected ("a record name", advance ts))
      | (WKey "from", _) =>
          (case (peek (advance ts), peek (advance (advance ts)), peek (advance (advance (advance ts)))) of
             ((WScon (SString file), _), (WKey "import", _), (WKey "*", _)) =>
               let val rest = advance (advance (advance (advance ts))) in
                 if isKey ("as", rest) then
                   bind (expect (";", advance (advance rest))) (fn _ => fn ts => Done ([], ts))
                 else
                   bind (expect (";", rest)) (fn _ => fn ts =>
                     Done ([DOpen (p, [[structureName file]])], ts))
               end
           | _ => Fail ("only `from \"./file.wm\" import *` imports have a SubsetML counterpart", p))
      | _ => expected ("a declaration", ts)
    end

  (* `<a, b>` after a type name. *)
  and typeParams = fn ts =>
    if isKey ("<", ts) then
      delimited ("<", fn ts =>
                   case peek ts of
                     (WName [v], _) => Done ("'" ^ v, advance ts)
                   | _ => expected ("a type parameter", ts), ",", ">", ts)
    else Done ([], ts)

  (* `type` bindings: aliases, or datatypes when the body has `|`. *)
  and parseTypeDecl = fn (p, ts) =>
    let
      (* `C` or `C<T1, ..., Tn>`; several arguments are one tuple payload. *)
      val constructor = fn ts =>
        case peek ts of
          (WName [c], cp) =>
            if not (isUpperName c) then expected ("a constructor", ts)
            else
              (if isKey ("<", advance ts) then
                 bind (delimited ("<", parseType, ",", ">", advance ts)) (fn args => fn ts =>
                   case args of
                     [single] => Done ((cp, c, SOME single), ts)
                   | _ => Done ((cp, c, SOME (TyTuple args)), ts))
               else Done ((cp, c, NONE), advance ts))
        | _ => expected ("a constructor", ts)
      val rec members = fn (acc, ts) =>
        if isKey ("|", ts) then
          bind (constructor (advance ts)) (fn c => fn ts => members (c :: acc, ts))
        else Done (SmlList.rev acc, ts)
      val binding = fn ts =>
        case peek ts of
          (WName [name], _) =>
            bind (typeParams (advance ts)) (fn vs => fn ts =>
              bind (expect ("=", ts)) (fn _ => fn body =>
                if isKey ("|", body) then
                  bind (members ([], body)) (fn cons => fn ts => Done ((vs, decapitalize name, NONE, cons), ts))
                else
                  (* Without a leading `|`, a body with no `|` is an alias. *)
                  bind (parseType body) (fn t => fn ts =>
                    if isKey ("|", ts) then
                      bind (constructor body) (fn first => fn ts =>
                        bind (members ([first], ts)) (fn cons => fn ts =>
                          Done ((vs, decapitalize name, NONE, cons), ts)))
                    else Done ((vs, decapitalize name, SOME t, []), ts))))
        | _ => expected ("a type name", ts)
      val rec bindings = fn ts =>
        bind (binding ts) (fn b => fn ts =>
          if isKey ("and", ts) then bind (bindings (advance ts)) (fn bs => fn ts => Done (b :: bs, ts))
          else Done ([b], ts))
    in
      bind (bindings ts) (fn bs => fn ts =>
        bind (expect (";", ts)) (fn _ => fn ts =>
          case (SmlList.all (fn (_, _, alias, _) => SmlOption.isSome alias) bs,
                SmlList.all (fn (_, _, alias, _) => not (SmlOption.isSome alias)) bs) of
            (true, _) => Done ([DType (p, SmlList.map (fn (vs, n, alias, _) => let val SOME t = alias in (vs, n, t) end) bs)], ts)
          | (_, true) => Done ([DDatatype (p, SmlList.map (fn (vs, n, _, cons) => (vs, n, cons)) bs)], ts)
          | _ => Fail ("SubsetML cannot mix type aliases and datatypes in one group", p)))
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Modules *)

  datatype result =
      Module of dec list * exp list * comment list
    | ParseError of string * pos

  val parseModule = fn src =>
    case WmLexer.lex src of
      LexError (message, pos) => ParseError (message, pos)
    | Tokens (ts, comments) =>
        let
          val rec items = fn (decs, exps, ts) =>
            case peek ts of
              (WEOF, _) => Done ((SmlList.rev decs, SmlList.rev exps), ts)
            | _ =>
                if startsDecl ts orelse isKey ("from", ts)
                then bind (parseDecl ts) (fn ds => fn ts => items (SmlList.revAppend (ds, decs), exps, ts))
                else
                  bind (parseExp ts) (fn e => fn ts =>
                    bind (expect (";", ts)) (fn _ => fn ts => items (DVal (0.0, [], [(PId (0.0, ([], "it")), e)], []) :: decs, exps, ts)))
        in
          case items ([], [], ts) of
            Done ((decs, exps), _) => Module (decs, exps, comments)
          | Fail (message, pos) => ParseError (message, pos)
        end

end
