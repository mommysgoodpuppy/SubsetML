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
      t :: ignored1 => t
    | [] => (WEOF, 0.0)

  val advance = fn
      ignored2 :: rest => rest
    | [] => []

  val posOf = fn ts => let val (ignored3, p) = peek ts in p end

  val isKey = fn (k, ts) =>
    case peek ts of
      (WKey k', ignored4) => k = k'
    | ignored5 => false

  val describe = fn
      WKey k => "`" ^ k ^ "`"
    | WName path => "`" ^ SubsetString.concatWith (path, ".") ^ "`"
    | WSelect l => "`#" ^ l ^ "`"
    | WScon ignored6 => "a literal"
    | WSml ignored7 => "an SML declaration"
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
    bind (expect (openK, ts)) (fn ignored8 => fn ts =>
      bind (separated (item, sep, close, ts)) (fn xs => fn ts =>
        bind (expect (close, ts)) (fn ignored9 => fn ts => Done (xs, ts))))

  (* --------------------------------------------------------------------------------------- *)
  (* Names (the inverse of WmPrint's) *)

  val isUpperName = fn s => CompilerText.firstIs (s, SubsetChar.isUpper)

  val decapitalize = fn s =>
    case CompilerText.characters s of [] => "" | c :: rest => CompilerText.stringOf (SubsetChar.toLower c :: rest)

  val valueName = fn
      ([], "None") => ([], "NONE")
    | ([], "Some") => ([], "SOME")
    | id =>
        (case SmlList.find (fn (ignored10, wm) => wm = id) WmPrint.numNames of
           SOME entry => let val (sml, ignoredMapping) = entry in sml end
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
          last :: ignored11 => last
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
      (WKey "(", ignored12) =>
        bind (delimited ("(", parseType, ",", ")", ts)) (fn types => fn ts =>
          case types of
            [single] => Done (single, ts)
          | [] => expected ("a type", ts)
          | ignored13 => Done (TyTuple types, ts))
    | (WName [v], ignored14) =>
        if isUpperName v then typeName ([], v, advance ts) else Done (TyVar ("'" ^ v), advance ts)
    | (WName path, ignored15) =>
        (case SmlList.rev path of
           last :: rest => typeName (SmlList.rev rest, last, advance ts)
         | [] => expected ("a type", ts))
    | ignored16 => expected ("a type", ts)

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
    | ignored17 => c

  val negativeLiteral = fn (minusPos, ts) =>
    case peek ts of
      (WScon (SInt s), p) => if Real.== (p, minusPos + 1.0) then SOME (SReal ("~" ^ s ^ ".0")) else NONE
    | (WScon (SReal s), p) => if Real.== (p, minusPos + 1.0) then SOME (SReal ("~" ^ s)) else NONE
    | ignored18 => NONE

  (* Builds `h1 :: ... :: tail`. *)
  val consPat = fn (p, items, tail) =>
    SmlList.foldr (fn (h, t) => PApp (p, ([], "::"), PTuple [h, t])) tail items

  (* `[a, b, ..tail]` after the `[`: the items and the optional spread tail. *)
  val listItems = fn (item, ts) =>
    let
      val rec go = fn (acc, ts) =>
        case peek ts of
          (WKey "]", ignored19) => Done ((SmlList.rev acc, NONE), advance ts)
        | (WKey "..", ignored20) =>
            bind (item (advance ts)) (fn t => fn ts =>
              bind (expect ("]", if isKey (",", ts) then advance ts else ts)) (fn ignored21 => fn ts =>
                Done ((SmlList.rev acc, SOME t), ts)))
        | ignored22 =>
            (case item ts of
               Done (x, rest) =>
                 if isKey (",", rest) then go (x :: acc, advance rest)
                 else bind (expect ("]", rest)) (fn ignored23 => fn rest => Done ((SmlList.rev (x :: acc), NONE), rest))
             | Fail (message, offset) => Fail (message, offset))
    in
      go ([], ts)
    end

  val rec parsePat = fn (inMatch, binds, ts) =>
    let val child = fn b => fn ts => parseAnnotated (inMatch, b orelse not inMatch, ts) in
      case peek ts of
        (WKey "_", ignored24) => Done (PWild, advance ts)
      | (WKey "void", ignored25) => Done (PTuple [], advance ts)
      | (WKey "true", p) => Done (PId (p, ([], "true")), advance ts)
      | (WKey "false", p) => Done (PId (p, ([], "false")), advance ts)
      | (WScon (SInt ignored26), p) => Fail ("real constants may not occur in patterns", p)
      | (WScon (SReal ignored27), p) => Fail ("real constants may not occur in patterns", p)
      | (WScon c, p) => Done (PScon (p, c), advance ts)
      | (WKey "-", p) =>
          (case negativeLiteral (p, advance ts) of
             SOME (SInt s) => Done (PScon (p, SInt s), advance (advance ts))
           | ignored28 => expected ("a pattern", ts))
      | (WKey ".{", p) =>
          let
            val field = fn ts =>
              case peek ts of
                (WName [l], lp) =>
                  if isKey ("=", advance ts) then
                    bind (child false (advance (advance ts))) (fn q => fn ts => Done ((l, q), ts))
                  else Done ((l, PId (lp, ([], l))), advance ts)
              | ignored29 => expected ("a record field", ts)
          in
            bind (separated (field, ",", "}", advance ts)) (fn fields => fn ts =>
              bind (expect ("}", ts)) (fn ignored30 => fn ts => Done (PRecord (p, fields), ts)))
          end
      | (WKey "[", p) =>
          bind (listItems (child true, advance ts)) (fn (items, tail) => fn ts =>
            case tail of
              NONE => Done (PList items, ts)
            | SOME t => Done (consPat (p, items, t), ts))
      | (WKey "(", ignored31) =>
          bind (delimited ("(", child false, ",", ")", ts)) (fn ps => fn ts =>
            case ps of
              [single] => Done (single, ts)
            | ignored32 => Done (PTuple ps, ts))
      | (WName ["Var"], ignored33) =>
          (case (peek (advance ts), peek (advance (advance ts)), peek (advance (advance (advance ts)))) of
             ((WKey "(", ignored34), (WName [x], p), (WKey ")", ignored35)) =>
               Done (PId (p, ([], x)), advance (advance (advance (advance ts))))
           | ignored36 => expected ("`Var(name)`", ts))
      | (WName path, p) =>
          let
            val name :: reversedQuals = SubsetList.reverse path
            val quals = SubsetList.reverse reversedQuals
          in
            case (isUpperName name, binds, SmlList.null quals) of
              (true, ignored37, ignored38) =>
                if isKey ("(", advance ts) then
                  bind (delimited ("(", child true, ",", ")", advance ts)) (fn args => fn ts =>
                    case args of
                      [single] => Done (PApp (p, valueName (quals, name), single), ts)
                    | ignored39 => Done (PApp (p, valueName (quals, name), PTuple args), ts))
                else Done (PId (p, valueName (quals, name)), advance ts)
            | (false, true, true) => Done (PId (p, ([], name)), advance ts)
            | (false, ignored40, ignored41) =>
                Fail ("`" ^ SubsetString.concatWith (path, ".") ^ "` here is a pinned value in Workman, "
                      ^ "which SubsetML patterns cannot express; write Var(" ^ name ^ ") to bind", p)
          end
      | ignored42 => expected ("a pattern", ts)
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
          (WEOF, ignored43) => false
        | (WKey k, ignored44) =>
            if k = "(" orelse k = "[" orelse k = "{" orelse k = ".{" then scan (depth + 1.0, advance ts)
            else
              (if k = ")" orelse k = "]" orelse k = "}" then
                 (if Real.== (depth, 1.0) then isKey ("=>", advance ts) else scan (depth - 1.0, advance ts))
               else scan (depth, advance ts))
        | ignored45 => scan (depth, advance ts)
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
    | ignored46 => NONE

  val smlOperator = fn
      "==" => "="
    | "!=" => "<>"
    | "++" => "^"
    | s => s

  (* The SML operators WmPrint keeps where Workman has none. *)
  val fallbackOperator = fn ts =>
    case peek ts of
      (WKey "@", ignored47) => SOME "@"
    | (WName [s], ignored48) => if s = "div" orelse s = "mod" orelse s = "o" orelse s = "before" then SOME s else NONE
    | ignored49 => NONE

  val infixApp = fn (opr, p, l, r) => EApp (EId (p, ([], opr)), ETuple [l, r])

  val consExp = fn (p, items, tail) =>
    SmlList.foldr (fn (h, t) => infixApp ("::", p, h, t)) tail items

  val startsDecl = fn ts =>
    isKey ("let", ts) orelse isKey ("type", ts) orelse isKey ("record", ts)
    orelse (case peek ts of (WSml ignored50, ignored51) => true | ignored52 => false)

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
        | (ignored53, ignored54) => es @ [blockExp (after, terminated)]
    in
      case (ds, body) of
        ([], [single]) => single
        | ignored55 => ELet (ds, body)
    end

  val rec parseExp = fn ts =>
    case peek ts of
      (WKey "if", ignored56) =>
        bind (expect ("(", advance ts)) (fn ignored57 => fn ts =>
          bind (parseExp ts) (fn c => fn ts =>
            bind (expect (")", ts)) (fn ignored58 => fn ts =>
              bind (parseBlock ts) (fn a => fn ts =>
                bind (expect ("else", ts)) (fn ignored59 => fn ts =>
                  bind (parseBlock ts) (fn b => fn ts => Done (EIf (c, a, b), ts)))))))
    | (WKey "match", ignored60) =>
        if isKey ("{", advance ts) then
          bind (parseArms (advance ts)) (fn rules => fn ts => Done (EFn rules, ts))
        else
          (if lambdaAhead (advance ts) then parseMatchFunction (advance ts)
           else
             bind (delimited ("(", parseExp, ",", ")", advance ts)) (fn values => fn ts =>
               bind (parseArms ts) (fn rules => fn ts =>
                 case values of
                   [single] => Done (ECase (single, rules), ts)
                 | ignored61 => Done (ECase (ETuple values, rules), ts))))
    | (WKey "(", ignored62) => if lambdaAhead ts then parseLambda ts else parseFallback ts
    | ignored63 => parseFallback ts

  (* `match(x, y) => { arms }`: a function of its named parameters. *)
  and parseMatchFunction = fn ts =>
    let
      val name = fn ts =>
        case peek ts of
          (WName [x], p) => Done ((p, x), advance ts)
        | ignored64 => expected ("a parameter name", ts)
    in
      bind (delimited ("(", name, ",", ")", ts)) (fn names => fn ts =>
        bind (expect ("=>", ts)) (fn ignored65 => fn ts =>
          bind (parseArms ts) (fn rules => fn ts =>
            let
              val param =
                case names of
                  [(p, x)] => PId (p, ([], x))
                | ignored66 => PTuple (SmlList.map (fn (p, x) => PId (p, ([], x))) names)
              val value =
                case names of
                  [(p, x)] => EId (p, ([], x))
                | ignored67 => ETuple (SmlList.map (fn (p, x) => EId (p, ([], x))) names)
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
        bind (expect ("=>", ts)) (fn ignored68 => fn ts =>
          bind (if lambdaAhead ts then parseLambda ts else parseBlock ts) (fn body => fn ts =>
            let
              val p =
                case ps of
                  [single] => single
                | ignored69 => PTuple ps
            in
              Done (EFn [(p, body)], ts)
            end)))
    end

  and parseArms = fn ts =>
    let
      val arm = fn ts =>
        bind (parseAnnotated (true, false, ts)) (fn p => fn ts =>
          bind (expect ("=>", ts)) (fn ignored70 => fn ts =>
            bind (parseBlock ts) (fn e => fn ts => Done ((p, e), ts))))
    in
      delimited ("{", arm, ",", "}", ts)
    end

  and parseBlock = fn ts =>
    let
      val rec items = fn (acc, ts) =>
        case peek ts of
          (WKey "}", ignored71) => Done ((SmlList.rev acc, true), advance ts)
        | ignored72 =>
            if startsDecl ts then
              bind (parseDecl ts) (fn ds => fn ts => items (SmlList.map IDec ds @ acc, ts))
            else
              bind (parseExp ts) (fn e => fn ts =>
                if isKey (";", ts) then items (IExp e :: acc, advance ts)
                else bind (expect ("}", ts)) (fn ignored73 => fn ts => Done ((SmlList.rev (IExp e :: acc), false), ts)))
    in
      bind (expect ("{", ts)) (fn ignored74 => fn ts =>
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
                              | ignored75 =>
                                  case (opr, l) of
                                    ("==", ETyped (x, TyCon ([], ([], "real")))) =>
                                      EApp (EId (p, (["Real"], "==")), ETuple [x, r])
                                  | ("!=", ETyped (x, TyCon ([], ([], "real")))) =>
                                      EApp (EId (p, (["Real"], "!=")), ETuple [x, r])
                                  | ignored76 => infixApp (smlOperator opr, p, l, r), ts)))
             | NONE => Done (l, ts))
        | ignored77 => Done (l, ts)
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
    | ignored78 => parsePostfix ts

  (* A primary expression followed by calls. *)
  and parsePostfix = fn ts =>
    let
      val rec calls = fn (f, ts) =>
        if isKey ("(", ts) andalso not (lambdaAhead ts) then
          bind (delimited ("(", parseExp, ",", ")", ts)) (fn args => fn ts =>
            case (f, args) of
              (* WmPrint's spelling of SML `@`; the SML Basis has no List.append. *)
              (EId (p, (["List"], "append")), [l, r]) => calls (infixApp ("@", p, l, r), ts)
            | (ignored79, [single]) => calls (EApp (f, single), ts)
            | ignored80 => calls (EApp (f, ETuple args), ts))
        else Done (f, ts)
    in
      bind (parsePrimary ts) (fn e => fn ts => calls (e, ts))
    end

  and parsePrimary = fn ts =>
    case peek ts of
      (WScon c, p) => Done (EScon (p, number c), advance ts)
    | (WKey "true", p) => Done (EId (p, ([], "true")), advance ts)
    | (WKey "false", p) => Done (EId (p, ([], "false")), advance ts)
    | (WKey "void", ignored81) => Done (ETuple [], advance ts)
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
            | ignored82 => expected ("a record field", ts)
        in
          bind (separated (field, ",", "}", advance ts)) (fn fields => fn ts =>
            bind (expect ("}", ts)) (fn ignored83 => fn ts => Done (ERecord (p, fields), ts)))
        end
    | (WKey "{", ignored84) => parseBlock ts
    | (WKey "(", ignored85) =>
        bind (parseExp (advance ts)) (fn first => fn ts =>
          case peek ts of
            (WKey ":", ignored86) =>
              bind (parseType (advance ts)) (fn t => fn ts =>
                bind (expect (")", ts)) (fn ignored87 => fn ts => Done (ETyped (first, t), ts)))
          | (WKey ",", ignored88) =>
              bind (separated (parseExp, ",", ")", advance ts)) (fn rest => fn ts =>
                bind (expect (")", ts)) (fn ignored89 => fn ts => Done (ETuple (first :: rest), ts)))
          | (WKey ";", ignored90) =>
              bind (separated (parseExp, ";", ")", advance ts)) (fn rest => fn ts =>
                bind (expect (")", ts)) (fn ignored91 => fn ts => Done (ESeq (first :: rest), ts)))
          | ignored92 => bind (expect (")", ts)) (fn ignored93 => fn ts => Done (first, ts)))
    | (WKey "if", ignored94) => parseExp ts
    | (WKey "match", ignored95) => parseExp ts
    | ignored96 => expected ("an expression", ts)

  (* --------------------------------------------------------------------------------------- *)
  (* Declarations. A namespace import (`import * as X`) yields no declaration: SML refers to
     structures by name without importing them. *)

  and parseDecl = fn ts =>
    let val p = posOf ts in
      case peek ts of
        (WSml text, ignored97) =>
          (case Parser.parse text of
             Parser.Program (prog, ignored98) =>
               Done (SmlList.concat (SmlList.map (fn
                         TopDecs sds => SmlList.concat (SmlList.map (fn SDec d => [d] | SStructure (ignored99Field0, ignored99Field1) => []) sds)
                       | TopExp (ignored100Field0, ignored100Field1) => []) prog), advance ts)
           | Parser.ParseError (msg, q) => Fail ("in an SML declaration: " ^ msg, p + q))
      | (WKey "let", ignored101) =>
          let
            val isRec = isKey ("rec", advance ts)
            val binding = fn ts =>
              bind (parsePat (false, true, ts)) (fn pat => fn ts =>
                let
                  val rhs = fn (pat, ts) =>
                    bind (expect ("=", ts)) (fn ignored102 => fn ts =>
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
              bind (expect (";", ts)) (fn ignored103 => fn ts =>
                if isRec then
                  (if SmlList.all (fn (ignored104, e) => case e of EFn ignored105 => true | ignored106 => false) bs
                   then Done ([DVal (p, [], [], bs)], ts)
                   else Fail ("the right side of a `let rec` binding must be a function", p))
                else Done ([DVal (p, [], bs, [])], ts)))
          end
      | (WKey "type", ignored107) => parseTypeDecl (p, advance ts)
      | (WKey "record", ignored108) =>
          (case peek (advance ts) of
             (WName [name], ignored109) =>
               bind (typeParams (advance (advance ts))) (fn vs => fn ts =>
                 bind (expect ("=", ts)) (fn ignored110 => fn ts =>
                   let
                     val field = fn ts =>
                       case peek ts of
                         (WName [l], ignored111) =>
                           bind (expect (":", advance ts)) (fn ignored112 => fn ts =>
                             bind (parseType ts) (fn t => fn ts => Done ((l, t), ts)))
                       | ignored113 => expected ("a record field", ts)
                   in
                     bind (delimited ("{", field, ",", "}", ts)) (fn fields => fn ts =>
                       bind (expect (";", ts)) (fn ignored114 => fn ts =>
                         Done ([DType (p, [(vs, decapitalize name, TyRecord fields)])], ts)))
                   end))
           | ignored115 => expected ("a record name", advance ts))
      | (WKey "from", ignored116) =>
          (case (peek (advance ts), peek (advance (advance ts)), peek (advance (advance (advance ts)))) of
             ((WScon (SString file), ignored117), (WKey "import", ignored118), (WKey "*", ignored119)) =>
               let val rest = advance (advance (advance (advance ts))) in
                 if isKey ("as", rest) then
                   bind (expect (";", advance (advance rest))) (fn ignored120 => fn ts => Done ([], ts))
                 else
                   bind (expect (";", rest)) (fn ignored121 => fn ts =>
                     Done ([DOpen (p, [[structureName file]])], ts))
               end
           | ignored122 => Fail ("only `from \"./file.wm\" import *` imports have a SubsetML counterpart", p))
      | ignored123 => expected ("a declaration", ts)
    end

  (* `<a, b>` after a type name. *)
  and typeParams = fn ts =>
    if isKey ("<", ts) then
      delimited ("<", fn ts =>
                   case peek ts of
                     (WName [v], ignored124) => Done ("'" ^ v, advance ts)
                   | ignored125 => expected ("a type parameter", ts), ",", ">", ts)
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
                   | ignored126 => Done ((cp, c, SOME (TyTuple args)), ts))
               else Done ((cp, c, NONE), advance ts))
        | ignored127 => expected ("a constructor", ts)
      val rec members = fn (acc, ts) =>
        if isKey ("|", ts) then
          bind (constructor (advance ts)) (fn c => fn ts => members (c :: acc, ts))
        else Done (SmlList.rev acc, ts)
      val binding = fn ts =>
        case peek ts of
          (WName [name], ignored128) =>
            bind (typeParams (advance ts)) (fn vs => fn ts =>
              bind (expect ("=", ts)) (fn ignored129 => fn body =>
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
        | ignored130 => expected ("a type name", ts)
      val rec bindings = fn ts =>
        bind (binding ts) (fn b => fn ts =>
          if isKey ("and", ts) then bind (bindings (advance ts)) (fn bs => fn ts => Done (b :: bs, ts))
          else Done ([b], ts))
    in
      bind (bindings ts) (fn bs => fn ts =>
        bind (expect (";", ts)) (fn ignored131 => fn ts =>
          case (SmlList.all (fn (ignored132, ignored133, alias, ignored134) => SmlOption.isSome alias) bs,
                SmlList.all (fn (ignored135, ignored136, alias, ignored137) => not (SmlOption.isSome alias)) bs) of
            (true, ignored138) => Done ([DType (p, SmlList.map (fn (vs, n, alias, ignored139) => let val SOME t = alias in (vs, n, t) end) bs)], ts)
          | (ignored140, true) => Done ([DDatatype (p, SmlList.map (fn (vs, n, ignored141, cons) => (vs, n, cons)) bs)], ts)
          | ignored142 => Fail ("SubsetML cannot mix type aliases and datatypes in one group", p)))
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
              (WEOF, ignored143) => Done ((SmlList.rev decs, SmlList.rev exps), ts)
            | ignored144 =>
                if startsDecl ts orelse isKey ("from", ts)
                then bind (parseDecl ts) (fn ds => fn ts => items (SmlList.revAppend (ds, decs), exps, ts))
                else
                  bind (parseExp ts) (fn e => fn ts =>
                    bind (expect (";", ts)) (fn ignored145 => fn ts => items (DVal (0.0, [], [(PId (0.0, ([], "it")), e)], []) :: decs, exps, ts)))
        in
          case items ([], [], ts) of
            Done ((decs, exps), ignored146) => Module (decs, exps, comments)
          | Fail (message, pos) => ParseError (message, pos)
        end

end
