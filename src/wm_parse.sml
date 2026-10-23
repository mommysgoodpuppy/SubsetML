(* @subsetml
from "./syntax.sml" import * as Syntax;
from "./wm_lexer.sml" import * as WmLexer;
from "./subset_string.sml" import * as SubsetString;
from "./sml_list.sml" import * as SmlList;
from "./compiler_text.sml" import * as CompilerText;
from "./subset_char.sml" import * as SubsetChar;
from "./wm_print.sml" import * as WmPrint;
from "./backend_names.sml" import * as BackendNames;
from "./subset_list.sml" import * as SubsetList;
from "./sml_option.sml" import * as SmlOption;
*)

(* Parsing Workman source into SubsetML abstract syntax: the reverse of WmPrint.

   It accepts the Workman fragment that corresponds to SubsetML, plus the expression compatibility forms that
   WmPrint emits (`div`, `mod`, `@`, `o`, `before`, `#lab`, `~`). Workman features outside
   the reverse profile (`%`, receiver pipes, JSON, FFI imports, ...) are reported as errors.
   Numeric and pinned match patterns survive internally until binding resolution lowers them. *)
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
    | [] => (WEOF, 0)

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
    | WOpen _ => "a resolved header open"
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
    | ([], "I32") => ([], "int")
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
      val stem = if CompilerText.isSuffix (base, ".wm") then CompilerText.slice (base, 0, CompilerText.size base - 3) else base
    in BackendNames.moduleHint stem
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

  (* A bare Workman integer literal is an SML int when it fits in I32 and real otherwise, so
     `1` is int and `1.0` is real. Workman itself types `1` from context and defaults it to
     Number, so Number code read here must spell its integral constants `1.0`. *)
  val number = fn c =>
    case c of
      SInt s => if CompilerText.int32Literal s then c else SReal (s ^ ".0")
    | _ => c

  val negativeLiteral = fn (minusPos, ts) =>
    case peek ts of
      (WScon (SInt s), p) => if (p = minusPos + 1) then SOME (number (SInt ("~" ^ s))) else NONE
    | (WScon (SReal s), p) => if (p = minusPos + 1) then SOME (SReal ("~" ^ s)) else NONE
    | _ => NONE

  (* The text of an integer literal at the start of `ts`, `-` included: `(n: I32)` is an SML int
     constant even outside the range a bare literal reads as int. *)
  val integerText = fn ts =>
    case peek ts of
      (WScon (SInt s), _) => SOME s
    | (WKey "-", p) => (case peek (advance ts) of
        (WScon (SInt s), q) => if q = p + 1 then SOME ("~" ^ s) else NONE
      | _ => NONE)
    | _ => NONE

  val isIntType = fn t => case t of TyCon ([], ([], "int")) => true | _ => false

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
      | (WScon (SInt s), p) => Done (PScon (p, number (SInt s)), advance ts)
      | (WScon (SReal s), p) => Done (PScon (p, SReal s), advance ts)
      | (WScon c, p) => Done (PScon (p, c), advance ts)
      | (WKey "-", p) =>
          (case negativeLiteral (p, advance ts) of
             SOME c => Done (PScon (p, c), advance (advance ts))
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
                else Done (if inMatch then PPinned (p, valueName (quals, name))
                          else PId (p, valueName (quals, name)), advance ts)
            | (false, true, true) => Done (PId (p, ([], name)), advance ts)
            | (false, _, _) =>
                Done (PPinned (p, valueName (quals, name)), advance ts)
          end
      | _ => expected ("a pattern", ts)
    end

  (* A pattern that may carry a type annotation, as inside parentheses. *)
  and parseAnnotated = fn (inMatch, binds, ts) =>
    bind (parsePat (inMatch, binds, ts)) (fn p => fn rest =>
      if isKey (":", rest) then
        bind (parseType (advance rest)) (fn t => fn after =>
          Done (case (p, isIntType t, integerText ts) of
                  (PScon (q, _), true, SOME s) => PScon (q, SInt s)
                | _ => PTyped (p, t), after))
      else Done (p, rest))

  (* --------------------------------------------------------------------------------------- *)
  (* Expressions *)

  (* Whether the `(` at the head of ts begins a lambda, i.e. its matching `)` is followed by `=>`. *)
  val lambdaAhead = fn ts =>
    let
      val rec scan = fn (depth, ts) =>
        case peek ts of
          (WEOF, _) => false
        | (WKey k, _) =>
            if k = "(" orelse k = "[" orelse k = "{" orelse k = ".{" then scan (depth + 1, advance ts)
            else
              (if k = ")" orelse k = "]" orelse k = "}" then
                 (if (depth = 1) then isKey ("=>", advance ts) else scan (depth - 1, advance ts))
               else scan (depth, advance ts))
        | _ => scan (depth, advance ts)
    in
      isKey ("(", ts) andalso scan (0, ts)
    end

  val binLevel = fn
      "||" => SOME 1
    | "&&" => SOME 2
    | "==" => SOME 3
    | "!=" => SOME 3
    | "<" => SOME 4
    | ">" => SOME 4
    | "<=" => SOME 4
    | ">=" => SOME 4
    | "++" => SOME 5
    | "+" => SOME 5
    | "-" => SOME 5
    | "*" => SOME 6
    | "/" => SOME 6
    | "%" => SOME 6
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

  (* Calls and syntax-only pipe insertion share the same argument convention. *)
  val apply = fn (callee, args) =>
    case (callee, args) of
      (EId (p, (["List"], "append")), [left, right]) => infixApp ("@", p, left, right)
    | (_, [single]) => EApp (callee, single)
    | _ => EApp (callee, ETuple args)

  val consExp = fn (p, items, tail) =>
    SmlList.foldr (fn (h, t) => infixApp ("::", p, h, t)) tail items

  val startsDecl = fn ts =>
    isKey ("let", ts) orelse isKey ("type", ts) orelse isKey ("record", ts)
    orelse (case peek ts of (WOpen _, _) => true | _ => false)

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

  datatype result =
      Module of dec list * exp list * comment list
    | ParseError of string * pos

  datatype recordLayout = Layout of string * string * string list * (string * ty) list
  datatype recordPart = Spread of exp | Field of string * exp

  (* Resolve uppercase generic parameter references before producing SML types. *)
  val rec parameterType = fn (variables, t) =>
    case t of
      TyCon ([], ([], name)) =>
        (case SmlList.find (fn v => decapitalize (CompilerText.drop (v, 1)) = name) variables of
           SOME v => TyVar v | NONE => t)
    | TyCon (args, name) => TyCon (SmlList.map (fn a => parameterType (variables, a)) args, name)
    | TyTuple types => TyTuple (SmlList.map (fn a => parameterType (variables, a)) types)
    | TyArrow (a, b) => TyArrow (parameterType (variables, a), parameterType (variables, b))
    | TyRecord fields => TyRecord (SmlList.map (fn (l, a) => (l, parameterType (variables, a))) fields)
    | TyVar _ => t

  val parseModuleLowering = fn (layouts, owner, src, lexed, fieldPrefix) =>
    let
      (* Export field-type witnesses through their owning record module. Consumers need
         not import private dependencies merely to type-check generated reconstruction. *)
      val fieldAlias = fn (recordName, label) =>
        case fieldPrefix of NONE => "" | SOME prefix =>
          prefix ^ "Field" ^ CompilerText.natural (CompilerText.size recordName) ^ "_" ^ recordName ^ "_" ^ label
      (* Names absent from the authored source cannot capture its bindings. *)
      val names = case lexed of
          Tokens (tokens, _) => SmlList.concat (SmlList.map
            (fn (WName path, _) => path | _ => []) tokens)
        | LexError (_, _) => []
      val fresh = fn name => BackendNames.avoid (names, name)
      val source = CompilerText.source src
      val spaceBefore = fn ts =>
        let val p = posOf ts in
          p > 0 andalso
            (WmLexer.isSpace (CompilerText.sub (source, p - 1)) orelse
             CompilerText.sub (source, p - 1) = #"/")
        end
      val startsSpaceArgument = fn ts =>
        spaceBefore ts andalso
          (case peek ts of
             (WName _, _) => (case fallbackOperator ts of NONE => true | SOME _ => false)
           | (WScon _, _) => true
           | (WKey k, _) => member (k, ["(", "[", "{", ".{", "true", "false", "void", "match"])
           | _ => false)

      (* Conservative source purity: constructor applications and other computed forms use
         ordered lowering until their value status can be resolved by the checker. *)
      val rec pure = fn e =>
        case e of
          EScon (_, _) => true
        | EId (_, _) => true
        | EFn _ => true
        | ERecord (_, fields) => SmlList.all (fn (_, value) => pure value) fields
        | EList values => SmlList.all pure values
        | ETuple values => SmlList.all pure values
        | ETyped (value, _) => pure value
        | _ => false
      val rec variablesIn = fn t =>
        case t of
          TyVar name => [name]
        | TyCon (args, _) => SmlList.concat (SmlList.map variablesIn args)
        | TyTuple args => SmlList.concat (SmlList.map variablesIn args)
        | TyArrow (a, b) => variablesIn a @ variablesIn b
        | TyRecord fields => SmlList.concat (SmlList.map (fn (_, t) => variablesIn t) fields)
      val argumentShape = fn t =>
        case t of TyVar _ => true
        | TyTuple args => SmlList.all (fn TyVar _ => true | _ => false) args
        | _ => false
      val literalLayout = fn (variables, fields) =>
        let val occurrences = SmlList.concat (SmlList.map (fn (_, t) => variablesIn t) fields) in
          SmlList.all (fn v => (SubsetList.length (SmlList.filter (fn n => n = v) occurrences) = 1)) variables
          andalso SmlList.all (fn (_, t) =>
            SubsetList.isEmpty (variablesIn t) orelse
            (case t of TyVar _ => true | TyArrow (a, TyVar _) => argumentShape a | _ => false)) fields
        end
      (* Imported layouts must be visible outside a literal's lowering helper too.
         Type aliases have no runtime effect and do not create record identities. *)
      val referenced =
        let
          val rec scan = fn tokens =>
            case tokens of
              (WName path, _) :: (WKey "{", _) :: rest => path :: scan rest
            | _ :: rest => scan rest
            | [] => []
        in case lexed of Tokens (tokens, _) => scan tokens | LexError (_, _) => [] end
      val aliases = SmlList.map (fn Layout (moduleName, name, parameters, _) =>
        DType (0, [(parameters, fresh ("subsetmlLayout_" ^ moduleName ^ "_" ^ name),
          TyCon (SmlList.map TyVar parameters, (CompilerText.fields (moduleName, fn c => c = #"."), name)))]))
        (SmlList.filter (fn Layout (moduleName, name, _, _) => moduleName <> owner andalso
          SmlList.exists (fn path =>
            let val (qs, n, _) = splitPath path in
              SubsetString.concatWith (qs, ".") = moduleName andalso decapitalize n = name
            end) referenced) layouts)

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
            bind (parseBinary (1, advance ts)) (fn r => fn ts' => more (infixApp (opr, posOf ts, l, r), ts'))
        | NONE => Done (l, ts)
    in
      bind (parseBinary (1, ts)) (fn l => fn ts => more (l, ts))
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
                      bind (parseBinary (level + 1, advance ts)) (fn r => fn ts =>
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
           SOME c =>
             if isKey (":>", advance (advance ts)) then
               bind (parseUnary (advance ts)) (fn e => fn ts => Done (EApp (EId (p, ([], "~")), e), ts))
             else Done (EScon (p, c), advance (advance ts))
         | NONE => bind (parseUnary (advance ts)) (fn e => fn ts => Done (EApp (EId (p, ([], "~")), e), ts)))
    | _ => parsePipe ts

  (* Pipes bind above unary/binary operators, chain left-to-right, and lower
     only to ordinary applications. No type-directed receiver/carrier lookup. *)
  and parsePipe = fn ts =>
    let
      val rec more = fn (left, ts) =>
        if isKey (":>", ts) then
          let val stage = advance ts in
            if isKey (".", stage) then
              Fail ("receiver pipes are outside the SubsetML translation profile; use a named function", posOf stage)
            else bind (parsePostfixForm stage) (fn (right, insertion) => fn rest =>
              more (case insertion of
                      SOME (callee, args) => apply (callee, left :: args)
                    | NONE => EApp (right, left), rest))
          end
        else Done (left, ts)
    in
      bind (parsePostfix ts) (fn left => fn ts => more (left, ts))
    end

  and parsePostfix = fn ts =>
    bind (parsePostfixForm ts) (fn (value, _) => fn rest => Done (value, rest))

  (* Retain just the outer call's source form until pipe insertion is decided.
     Grouping returns a primary with no insertion slot. A space application is
     a fully constructed stage; a final explicit call supplies an insertion slot. *)
  and parsePostfixForm = fn ts =>
    let
      (* Direct self tail calls, not `bind` continuations, so a long application chain
         runs in constant stack on the Workman backend too. *)
      val rec calls = fn (callee, insertion, ts) =>
        if isKey ("(", ts) andalso not (lambdaAhead ts) then
          (case delimited ("(", parseExp, ",", ")", ts) of
             Done (args, rest) => calls (apply (callee, args), SOME (callee, args), rest)
           | Fail (message, offset) => Fail (message, offset))
        else (if startsSpaceArgument ts then
          (case (if lambdaAhead ts then parseLambda ts else parsePrimary ts) of
             Done (arg, rest) => calls (EApp (callee, arg), NONE, rest)
           | Fail (message, offset) => Fail (message, offset))
        else Done ((callee, insertion), ts))
    in
      bind (parsePrimary ts) (fn value => fn rest => calls (value, NONE, rest))
    end

  and parsePrimary = fn ts =>
    case peek ts of
      (WScon c, p) => Done (EScon (p, number c), advance ts)
    | (WKey "true", p) => Done (EId (p, ([], "true")), advance ts)
    | (WKey "false", p) => Done (EId (p, ([], "false")), advance ts)
    | (WKey "void", _) => Done (ETuple [], advance ts)
    | (WKey "~", p) => Done (EId (p, ([], "~")), advance ts)
    | (WName path, p) =>
        if isKey ("{", advance ts) then parseNamedRecord (p, path, advance (advance ts))
        else Done (pathExp (p, path), advance ts)
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
            | (WKey "..", offset) => Fail
                ("record updates must name their record type: use Point { ..value, field = replacement }", offset)
            | _ => expected ("a record field", ts)
        in
          bind (separated (field, ",", "}", advance ts)) (fn fields => fn ts =>
            bind (expect ("}", ts)) (fn _ => fn ts => Done (ERecord (p, fields), ts)))
        end
    | (WKey "{", _) => parseBlock ts
    | (WKey "(", _) =>
        bind (parseExp (advance ts)) (fn first => fn rest =>
          case peek rest of
            (WKey ":", _) =>
              bind (parseType (advance rest)) (fn t => fn after =>
                bind (expect (")", after)) (fn _ => fn after =>
                  Done (case (first, isIntType t, integerText (advance ts)) of
                          (EScon (q, _), true, SOME s) => EScon (q, SInt s)
                        | _ => ETyped (first, t), after)))
          | (WKey ",", _) =>
              bind (separated (parseExp, ",", ")", advance rest)) (fn more => fn ts =>
                bind (expect (")", ts)) (fn _ => fn ts => Done (ETuple (first :: more), ts)))
          | (WKey ";", _) =>
              bind (separated (parseExp, ";", ")", advance rest)) (fn more => fn ts =>
                bind (expect (")", ts)) (fn _ => fn ts => Done (ESeq (first :: more), ts)))
          | _ => bind (expect (")", rest)) (fn _ => fn ts => Done (first, ts)))
    | (WKey "if", _) => parseExp ts
    | (WKey "match", _) => parseExp ts
    | _ => expected ("an expression", ts)

  (* Named record layout is explicit; no inference is needed to enumerate copied fields. *)
  and parseNamedRecord = fn (p, path, ts) =>
    let
      val (qualifiers, name, selections) = splitPath path
      val sourceOwner = if SubsetList.isEmpty qualifiers then owner else SubsetString.concatWith (qualifiers, ".")
      val candidate = SmlList.find (fn Layout (moduleName, recordName, _, _) =>
        moduleName = sourceOwner andalso recordName = decapitalize name) layouts
      val part = fn ts =>
        case peek ts of
          (WKey "..", _) => bind (parseExp (advance ts)) (fn e => fn ts => Done (Spread e, ts))
        | (WName [label], offset) =>
            if isKey ("=", advance ts) then
              bind (parseExp (advance (advance ts))) (fn e => fn ts => Done (Field (label, e), ts))
            else Done (Field (label, EId (offset, ([], label))), advance ts)
        | _ => expected ("a record field or spread", ts)
    in
      if not (SubsetList.isEmpty selections) then Fail ("expected a nominal record type name", p)
      else case candidate of
        NONE => Fail ("unknown record layout " ^ SubsetString.concatWith (path, ".") ^ "; supply its declaration when translating", p)
      | SOME (Layout (_, recordName, variables, fields)) =>
          bind (separated (part, ",", "}", ts)) (fn parts => fn ts =>
            bind (expect ("}", ts)) (fn _ => fn ts =>
              let
                val prefix = "subsetmlRecord" ^ CompilerText.natural p ^ "_"
                val parameters = SmlList.map (fn v => (v, "'" ^ fresh (prefix ^ CompilerText.drop (v, 1)))) variables
                val rec fieldType = fn t =>
                  case t of
                    TyVar v => (case SmlList.find (fn (old, _) => old = v) parameters of
                      SOME pair => let val (_, name) = pair in TyVar name end | NONE => t)
                  | TyCon (args, (qs, n)) =>
                      let val builtin = SmlList.exists (fn b => b = n) ["real", "string", "char", "bool", "unit", "list", "option"]
                          val qs = if SubsetList.isEmpty qs andalso not builtin andalso sourceOwner <> owner then [sourceOwner] else qs
                      in TyCon (SmlList.map fieldType args, (qs, n)) end
                  | TyTuple types => TyTuple (SmlList.map fieldType types)
                  | TyArrow (a, b) => TyArrow (fieldType a, fieldType b)
                  | TyRecord fs => TyRecord (SmlList.map (fn (l, t) => (l, fieldType t)) fs)
                val fieldFor = fn (label, t) =>
                  case fieldPrefix of
                    SOME _ => if sourceOwner <> owner then
                      TyCon (SmlList.map (fn (_, v) => TyVar v) parameters,
                        ([sourceOwner], fieldAlias (recordName, label)))
                      else fieldType t
                  | NONE => fieldType t
                val targetType = TyCon (SmlList.map (fn (_, v) => TyVar v) parameters, (qualifiers, recordName))
                val literal =
                  if literalLayout (variables, fields) then
                    let
                      val rec direct = fn remaining =>
                        case remaining of
                          [] => SOME []
                        | Spread _ :: _ => NONE
                        | Field (label, value) :: rest =>
                            if not (pure value) then NONE
                            else (case (SmlList.find (fn (l, _) => l = label) fields, direct rest) of
                              (SOME entry, SOME tail) =>
                                let
                                  val (_, t) = entry
                                  val value = if SubsetList.isEmpty (variablesIn t) then ETyped (value, fieldFor (label, t))
                                    else (case t of
                                      TyArrow (domain, TyVar _) =>
                                        let
                                          val arguments = case domain of TyTuple args => args | _ => [domain]
                                          val rec argumentNames = fn (index, remaining) =>
                                            case remaining of [] => [] | _ :: rest =>
                                              fresh (prefix ^ label ^ "Argument" ^ CompilerText.natural index)
                                                :: argumentNames (index + 1, rest)
                                          val bound = argumentNames (0, arguments)
                                          val patterns = SmlList.map (fn name => PId (p, ([], name))) bound
                                          val values = SmlList.map (fn name => EId (p, ([], name))) bound
                                          val pattern = case domain of TyTuple _ => PTuple patterns | _ =>
                                            let val [single] = patterns in single end
                                          val argument = case domain of TyTuple _ => ETuple values | _ =>
                                            let val [single] = values in single end
                                        in EFn [(pattern, EApp (value, argument))] end
                                    | _ => value)
                                in SOME ((label, value) :: tail) end
                            | _ => NONE)
                    in direct parts end
                  else NONE
                val rec finish = fn (remaining, index, bindings, values, explicit) =>
                  case remaining of
                    [] =>
                      (case SmlList.find (fn (label, _) => not (SmlList.exists (fn (l, _) => l = label) values)) fields of
                         SOME pair => let val (label, _) = pair in Fail ("missing record field " ^ label, p) end
                       | NONE =>
                           let
                             val ordered = SmlList.rev bindings
                             val patterns = SmlList.map (fn (pattern, _) => pattern) ordered
                             val arguments = SmlList.map (fn (_, argument) => argument) ordered
                             val pattern = case patterns of [single] => single | _ => PTuple patterns
                             val argument = case arguments of [single] => single | _ => ETuple arguments
                             val helper = fresh (prefix ^ "build")
                             val result = ETyped (ERecord (p, SmlList.map (fn (label, _) =>
                               let val SOME pair = SmlList.find (fn (l, _) => l = label) values
                                   val (_, value) = pair in (label, value) end) fields), targetType)
                             val layoutAlias = DType (p, [(SmlList.map (fn (_, v) => v) parameters,
                               fresh (prefix ^ "layout"), targetType)])
                             (* Generalize the layout parameters on the helper, not on its caller.
                                Arguments retain source order and are evaluated once, including
                                entries overwritten by a later spread. *)
                             val declaration = DVal (p, [], [(PId (p, ([], helper)),
                               EFn [(pattern, ELet ([layoutAlias], [result]))])], [])
                             val ordered = ELet ([declaration], [EApp (EId (p, ([], helper)), argument)])
                             (* Replaced or discarded entries can constrain outer weak variables.
                                A plain copy retains every entry in its emitted field wrappers. *)
                             val copy = (case parts of [Spread (EId (_, _))] => true | _ => false)
                               andalso SmlList.all (fn (_, TyArrow (_, _)) => true | _ => false) fields
                               andalso SmlList.all (fn Spread (EId (_, _)) => true
                                 | Field (_, value) => pure value | _ => false) parts
                             val final = SmlList.foldl (fn (part, values) =>
                               case part of Spread e => SmlList.map (fn (label, _) =>
                                 (label, EApp (ESelect (p, label), e))) fields
                               | Field (label, e) => (label, e) :: SmlList.filter (fn (l, _) => l <> label) values) [] parts
                           in Done ((case literal of
                             SOME fields => ERecord (p, fields)
                           | NONE => if copy then ECopy (p, ordered, ERecord (p, final), targetType)
                             else ordered), ts) end)
                  | part :: rest =>
                      let val temporary = fresh (prefix ^ CompilerText.natural index)
                          val value = EId (p, ([], temporary)) in
                        case part of
                          Spread e => finish (rest, index + 1,
                            (PTyped (PId (p, ([], temporary)), targetType), e) :: bindings,
                            SmlList.map (fn (label, _) => (label, EApp (ESelect (p, label), value))) fields, explicit)
                        | Field (label, e) =>
                            if SmlList.exists (fn l => l = label) explicit then Fail ("duplicate record field " ^ label, p)
                            else (case SmlList.find (fn (l, _) => l = label) fields of
                              NONE => Fail (name ^ " has no field " ^ label, p)
                            | SOME pair =>
                                let val (_, t) = pair in finish (rest, index + 1,
                                  (PTyped (PId (p, ([], temporary)), fieldFor (label, t)), e) :: bindings,
                                  (label, value) :: SmlList.filter (fn (l, _) => l <> label) values,
                                  label :: explicit) end)
                      end
                            in finish (parts, 0, [], [], []) end))
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Declarations. A namespace import (`import * as X`) yields no declaration: SML refers to
     structures by name without importing them. *)

  and parseDecl = fn ts =>
    let val p = posOf ts in
      case peek ts of
        (WOpen ids, _) => Done ([DOpen (p, ids)], advance ts)
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
                         Done (DType (p, [(vs, decapitalize name, TyRecord (SmlList.map (fn (l, t) => (l, parameterType (vs, t))) fields))]) ::
                           (case fieldPrefix of NONE => [] | SOME prefix =>
                             let
                               val arguments = SmlList.map (fn (label, _) =>
                                 (label, fresh (prefix ^ "Constructor_" ^ name ^ "_" ^ label))) fields
                               val patterns = SmlList.map (fn (_, argument) => PId (p, ([], argument))) arguments
                               val parameter = case patterns of [single] => single | _ => PTuple patterns
                               val target = TyCon (SmlList.map TyVar vs, ([], decapitalize name))
                               val body = ETyped (ERecord (p, SmlList.map (fn (label, argument) =>
                                 (label, EId (p, ([], argument)))) arguments), target)
                             in [DVal (p, [], [(PId (p, ([], name)), EFn [(parameter, body)])], [])] end) @
                           (case fieldPrefix of NONE => [] | SOME _ =>
                             SmlList.map (fn (label, t) => DType (p,
                               [(vs, fieldAlias (decapitalize name, label), parameterType (vs, t))])) fields), ts)))
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
            (true, _) => Done ([DType (p, SmlList.map (fn (vs, n, alias, _) => let val SOME t = alias in (vs, n, parameterType (vs, t)) end) bs)], ts)
          | (_, true) => Done ([DDatatype (p, SmlList.map (fn (vs, n, _, cons) => (vs, n,
              SmlList.map (fn (q, c, arg) => (q, c, case arg of
                SOME t => SOME (parameterType (vs, t)) | NONE => NONE)) cons)) bs)], ts)
          | _ => Fail ("SubsetML cannot mix type aliases and datatypes in one group", p)))
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Modules *)

    in case lexed of
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
                    bind (expect (";", ts)) (fn _ => fn ts => items (DVal (0, [], [(PId (0, ([], "it")), e)], []) :: decs, exps, ts)))
        in
          case items ([], [], ts) of
            Done ((decs, exps), _) => Module (aliases @ decs, exps, comments)
          | Fail (message, pos) => ParseError (message, pos)
        end
    end

  val parseModuleTokens = fn (layouts, owner, src, lexed) =>
    parseModuleLowering (layouts, owner, src, lexed, NONE)

  val parseModuleProject = fn (layouts, owner, src, lexed, prefix) =>
    parseModuleLowering (layouts, owner, src, lexed, SOME prefix)

  val parseModuleWithLayouts = fn (layouts, owner, src) =>
    parseModuleTokens (layouts, owner, src, WmLexer.lex src)

  (* Extract declaration layouts without requiring the rest of a module to translate yet.
     Complete expressions still pass through normal parsing and strict elaboration. *)
  val recordLayoutsTokens = fn (owner, src, lexed) =>
    let
      val rec scan = fn (tokens, layouts, depth) =>
        case tokens of
          (WKey "record", start) :: rest =>
            if depth > 0 then Fail ("record layout declarations must be top-level in the initial translation profile", start)
            else let
              val rec header = fn remaining =>
                case remaining of
                  (WKey ";", stop) :: tail =>
                    (case parseModuleTokens ([], owner, src, Tokens (
                      SubsetList.filter (tokens, fn (_, p) => p <= stop) @ [(WEOF, stop + 1)], [])) of
                       Module ([DType (_, [(variables, name, TyRecord fields)])], [], _) =>
                         scan (tail, Layout (owner, name, variables, fields) :: layouts, depth)
                     | Module (_, _, _) => Fail ("invalid record declaration", start)
                     | ParseError (message, offset) => Fail (message, offset))
                | (WEOF, offset) :: _ => Fail ("unterminated record declaration", offset)
                | _ :: tail => header tail
                | [] => Fail ("unterminated record declaration", start)
            in header rest end
        | (WKey "{", _) :: rest => scan (rest, layouts, depth + 1)
        | (WKey ".{", _) :: rest => scan (rest, layouts, depth + 1)
        | (WKey "}", _) :: rest => scan (rest, layouts, depth - 1)
        | _ :: rest => scan (rest, layouts, depth)
        | [] => Done (SmlList.rev layouts, [])
    in
      case lexed of
        LexError (message, offset) => Fail (message, offset)
      | Tokens (tokens, _) => scan (tokens, [], 0)
    end

  val recordLayouts = fn (path, src) =>
    recordLayoutsTokens (structureName path, src, WmLexer.lex src)

  val parseModule = fn src =>
    case recordLayouts ("", src) of
      Fail (message, offset) => ParseError (message, offset)
    | Done (layouts, _) => parseModuleWithLayouts (layouts, "", src)

end
