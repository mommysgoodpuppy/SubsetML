(* Prints abstract syntax as Workman source, following the frontend-v3 spelling
   (../wm-mini/tooling/frontend-v3/lexical-design.md). The mapping is designed to be read back
   by WmParse; docs/translation.md lists every rule.

   A construct with no Workman counterpart is printed in SML syntax instead (SmlPrint), so the
   output never silently changes meaning. *)
structure WmPrint = struct

  open Syntax
  open Doc

  (* --------------------------------------------------------------------------------------- *)
  (* Names *)

  val capitalize = fn s =>
    if s = "" then s else String.str (SubsetChar.toUpper (Num.String.sub (s, 0.0))) ^ Num.String.extract (s, 1.0, NONE)

  val dotted = fn (qs, s) => String.concatWith "." (qs @ [s])

  (* Type constructors are capitalized; the Definition's `unit` and the Basis `real` take
     Workman's names. *)
  val tyConName = fn
      ([], "unit") => "Void"
    | ([], "real") => "Number"
    | (qs, s) => dotted (qs, capitalize s)

  (* Numeric adapters retain SML argument order. Keep this table shared with the reader. *)
  val numNames =
    SmlList.concat (SmlList.map (fn (q, names) =>
      SmlList.map (fn x => ((["Num", q], x), ([q], x))) names)
      [("String", ["size", "sub", "substring", "extract"]),
       ("List", ["length", "nth", "take", "drop", "tabulate"]),
       ("Char", ["ord", "chr"]), ("CharVector", ["tabulate"])])
    @ SmlList.map (fn x => ((["Num"], x), (["Number"], x)))
        ["div", "mod", "toString", "fromString"]

  (* Basis constructors spelled differently in Workman. *)
  val valueName = fn
      ([], "NONE") => "None"
    | ([], "SOME") => "Some"
    | id =>
        (case SmlList.find (fn (sml, _) => sml = id) numNames of
           SOME (_, wm) => dotted wm
         | NONE => dotted id)

  (* Workman tells constructors from variables by case; SubsetML code follows the same
     convention, with the Definition's lowercase constructors as exceptions. *)
  val isConName = fn (qs, s) =>
    not (SmlList.null qs) orelse SubsetChar.isUpper (Num.String.sub (s, 0.0)) orelse s = "true" orelse s = "false"
    orelse s = "nil"

  (* `'a` is written `a`: Workman type variables are lowercase type names. *)
  val tyVarName = fn v => Num.String.extract (v, 1.0, NONE)

  (* --------------------------------------------------------------------------------------- *)
  (* Constants *)

  val minus = fn s => String.map (fn c => if c = #"~" then #"-" else c) s

  val hex2 = fn n =>
    let val digits = "0123456789abcdef" in
      String.implode [Num.String.sub (digits, Num.div (n, 16.0)), Num.String.sub (digits, Num.mod (n, 16.0))]
    end

  val escapeChar = fn (quote, c) =>
    case c of
      #"\n" => "\\n"
    | #"\t" => "\\t"
    | #"\r" => "\\r"
    | #"\\" => "\\\\"
    | _ =>
        if c = quote then "\\" ^ String.str c
        else (if SubsetChar.isPrint c then String.str c else "\\u00" ^ hex2 (let val SubsetResult.Ok code = SubsetChar.toCode c in code end))

  val scon = fn
      SInt s => minus s
    | SReal s => minus (if String.isSuffix ".0" s
                           then Num.String.substring (s, 0.0, Num.String.size s - 2.0) else s)
    | SString s => "\"" ^ String.concat (SmlList.map (fn c => escapeChar (#"\"", c)) (String.explode s)) ^ "\""
    | SChar c => "'" ^ escapeChar (#"'", c) ^ "'"

  val isNegative = fn
      SInt s => Num.String.sub (s, 0.0) = #"~"
    | SReal s => Num.String.sub (s, 0.0) = #"~"
    | _ => false

  (* --------------------------------------------------------------------------------------- *)
  (* Types *)

  val rec ty = fn
      TyVar v => text (tyVarName v)
    | TyCon ([], id) => text (tyConName id)
    | TyCon (args, id) => cats [text (tyConName id ^ "<"), join (", ", SmlList.map ty args), text ">"]
    | TyTuple ts => cats [text "(", join (", ", SmlList.map ty ts), text ")"]
    | TyArrow (TyArrow (a, b), c) => cats [text "(", ty (TyArrow (a, b)), text ") -> ", ty c]
    | TyArrow (a, b) => cats [ty a, text " -> ", ty b]
    | TyRecord fields =>
        group ("{", ",", "}", SmlList.map (fn (l, t) => cats [text (l ^ ": "), ty t]) fields)

  val typeParams = fn
      [] => ""
    | vs => "<" ^ String.concatWith ", " (SmlList.map tyVarName vs) ^ ">"

  (* --------------------------------------------------------------------------------------- *)
  (* Patterns

     `inMatch` says whether the pattern is in a match arm, where Workman pins bare names;
     `binds` says whether a bare name binds at this exact position. In a match arm that holds
     only for constructor arguments, list items and record field puns, so other binders are
     written `Var(x)`. *)

  val rec pat = fn (inMatch, binds, p) =>
    let val child = fn (b, q) => pat (inMatch, b orelse not inMatch, q) in
      case p of
        PWild => text "_"
      | PScon (pos, c) => atom (pos, scon c)
      | PId (pos, ([], "nil")) => atom (pos, "[]")
      | PId (pos, id) =>
          if isConName id orelse binds then atom (pos, valueName id)
          else cats [text "Var(", atom (pos, valueName id), text ")"]
      | PTuple [] => text "void"
      | PTuple ps => group ("(", ",", ")", SmlList.map (fn q => child (false, q)) ps)
      | PList ps => group ("[", ",", "]", SmlList.map (fn q => child (true, q)) ps)
      | PApp (pos, ([], "::"), PTuple [h, t]) =>
          let
            val rec spine = fn
                (PApp (_, ([], "::"), PTuple [h, t]), acc) => spine (t, h :: acc)
              | (PList items, acc) => (SmlList.rev acc @ items, NONE)
              | (PId (_, ([], "nil")), acc) => (SmlList.rev acc, NONE)
              | (tail, acc) => (SmlList.rev acc, SOME tail)
            val (items, tail) = spine (p, [])
            val itemDocs = SmlList.map (fn q => child (true, q)) items
            val tailDocs =
              case tail of
                NONE => []
              | SOME q => [cat (text "..", child (true, q))]
          in
            cat (atom (pos, ""), group ("[", ",", "]", itemDocs @ tailDocs))
          end
      | PApp (pos, id, PTuple (args :: more)) =>
          cats [atom (pos, valueName id),
                group ("(", ",", ")", SmlList.map (fn q => child (true, q)) (args :: more))]
      | PApp (pos, id, arg) => cats [atom (pos, valueName id), text "(", child (true, arg), text ")"]
      | PRecord (pos, fields) =>
          let
            val field = fn
                (l, PId (_, ([], x))) =>
                  if x = l andalso not (isConName ([], x)) then text l
                  else cats [text (l ^ " = "), child (false, PId (0.0, ([], x)))]
              | (l, q) => cats [text (l ^ " = "), child (false, q)]
          in
            cat (atom (pos, "."), group ("{ ", ",", " }", SmlList.map field fields))
          end
      | PTyped (q, t) => cats [text "(", child (false, q), text ": ", ty t, text ")"]
    end

  (* Patterns Workman accepts as lambda parameters: no constructors or constants. *)
  val rec paramOk = fn
      PWild => true
    | PId (_, id) => not (isConName id)
    | PTuple ps => SmlList.all paramOk ps
    | PList ps => SmlList.all paramOk ps
    | PRecord (_, fields) => SmlList.all (fn (_, q) => paramOk q) fields
    | PTyped (q, _) => paramOk q
    | PApp (_, ([], "::"), PTuple [h, t]) => paramOk h andalso paramOk t
    | _ => false

  (* A lambda parameter list: a tuple pattern is the list itself. *)
  val params = fn p =>
    let
      val item = fn
          PTyped (q, t) => cats [pat (false, true, q), text ": ", ty t]
        | q => pat (false, true, q)
    in
      case p of
        PTuple [] => text "()"
      | PTuple ps => group ("(", ",", ")", SmlList.map item ps)
      | _ => cats [text "(", item p, text ")"]
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Expressions

     Levels follow the Workman grammar: 0 for if, match, lambdas and SML fallbacks, then
     || 1, && 2, == != 3, comparisons 4, ++ + - 5, * / 6, prefix 7, calls 9, atoms 10. *)

  val binop = fn
      "=" => SOME ("==", 3.0)
    | "<>" => SOME ("!=", 3.0)
    | "<" => SOME ("<", 4.0)
    | ">" => SOME (">", 4.0)
    | "<=" => SOME ("<=", 4.0)
    | ">=" => SOME (">=", 4.0)
    | "+" => SOME ("+", 5.0)
    | "-" => SOME ("-", 5.0)
    | "^" => SOME ("++", 5.0)
    | "*" => SOME ("*", 6.0)
    | "/" => SOME ("/", 6.0)
    | _ => NONE

  val parenAt = fn (need : real, (level, d)) =>
    if level >= need then d else cats [text "(", d, text ")"]

  (* An expression usable as `e.lab`: a variable or a chain of such selections. *)
  val rec selectable = fn
      EId (_, id) => not (isConName id)
    | EApp (ESelect (_, l), e) => SubsetChar.isAlpha (Num.String.sub (l, 0.0)) andalso selectable e
    | _ => false

  (* The body of a block: a `let` contributes its declarations and expressions. *)
  val blockParts = fn
      ELet (ds, es) => (ds, es)
    | e => ([], [e])

  val rec expL = fn
      EScon (p, c) => (if isNegative c then 7.0 else 10.0, atom (p, scon c))
    | EId (p, ([], "nil")) => (10.0, atom (p, "[]"))
    | EId (p, (["Real"], opr)) =>
        if opr = "==" orelse opr = "!=" then
          let
            val realTy = TyCon ([], ([], "real"))
            val left = PTyped (PId (p, ([], "realLeft")), realTy)
            val right = PTyped (PId (p, ([], "realRight")), realTy)
          in
            expL (EFn [(PTuple [left, right],
              EApp (EId (p, (["Real"], opr)),
                    ETuple [EId (p, ([], "realLeft")), EId (p, ([], "realRight"))]))])
          end
        else (10.0, atom (p, valueName (["Real"], opr)))
    | EId (p, id) => (10.0, atom (p, valueName id))
    | ERecord (p, fields) =>
        (10.0, cat (atom (p, "."),
                  group ("{ ", ",", " }", SmlList.map (fn (l, e) => cats [text (l ^ " = "), exp e]) fields)))
    | ESelect (p, l) => (10.0, atom (p, "#" ^ l))
    | ETuple [] => (10.0, text "void")
    | ETuple es => (10.0, group ("(", ",", ")", SmlList.map exp es))
    | EList es => (10.0, group ("[", ",", "]", SmlList.map exp es))
    | ESeq es => (10.0, group ("(", ";", ")", SmlList.map exp es))
    | ELet (ds, es) => (10.0, block (ds, es))
    | EApp (EId (p, ([], "::")), ETuple [h, t]) =>
        let
          val rec spine = fn
              (EApp (EId (_, ([], "::")), ETuple [h, t]), acc) => spine (t, h :: acc)
            | (EList items, acc) => (SmlList.rev acc @ items, NONE)
            | (EId (_, ([], "nil")), acc) => (SmlList.rev acc, NONE)
            | (tail, acc) => (SmlList.rev acc, SOME tail)
          val (items, tail) = spine (EApp (EId (p, ([], "::")), ETuple [h, t]), [])
          val tailDocs =
            case tail of
              NONE => []
            | SOME e => [cat (text "..", exp e)]
        in
          (10.0, cat (atom (p, ""), group ("[", ",", "]", SmlList.map exp items @ tailDocs)))
        end
    | EApp (EId (p, (["Real"], opr)), ETuple [l, r]) =>
        if opr = "==" orelse opr = "!=" then
          let val left = case l of ETyped (x, TyCon ([], ([], "real"))) => x | _ => l in
            (3.0, cats [text "(", exp left, text ": Number)", atom (p, " " ^ opr ^ " "),
                        parenAt (4.0, expL r)])
          end
        else call (EId (p, (["Real"], opr)), ETuple [l, r])
    | EApp (EId (p, ([], opr)), ETuple [l, r]) =>
        (case (binop opr, Parser.isInfix opr) of
           (NONE, true) =>
             if opr = "@" then call (EId (p, (["List"], "append")), ETuple [l, r])
             else
               (* div, mod, o and before: no Workman operator, so the SML operator stays. *)
               (0.0, cats [parenAt (9.0, expL l), atom (p, " " ^ opr ^ " "), parenAt (9.0, expL r)])
         | (SOME (spelling, level), _) =>
             (level, cats [parenAt (level, expL l), atom (p, " " ^ spelling ^ " "),
                           parenAt (level + 1.0, expL r)])
         | (NONE, false) => call (EId (p, ([], opr)), ETuple [l, r]))
    | EApp (EId (p, ([], "not")), e) => (7.0, cat (atom (p, "!"), parenAt (7.0, expL e)))
    | EApp (EId (p, ([], "~")), e) =>
        let val (level, d) = expL e in
          (* `-3` would read back as a negative literal, so a literal operand keeps parentheses. *)
          (7.0, cat (atom (p, "-"),
                   case (e, level >= 9.0) of
                     (EScon _, _) => cats [text "(", d, text ")"]
                   | (_, true) => d
                   | (_, false) => cats [text "(", d, text ")"]))
        end
    | EApp (ESelect (p, l), e) =>
        if selectable e andalso SubsetChar.isAlpha (Num.String.sub (l, 0.0))
        then (10.0, cats [exp e, atom (p, "." ^ l)])
        else call (ESelect (p, l), e)
    | EApp (f, a) => call (f, a)
    | ETyped (e, t) => (10.0, cats [text "(", exp e, text ": ", ty t, text ")"])
    | EAndalso (a, b) => expL (EIf (a, b, EId (0.0, ([], "false"))))
    | EOrelse (a, b) => expL (EIf (a, EId (0.0, ([], "true")), b))
    | EIf (c, a, b) =>
        (0.0, cats [text "if (", exp c, text ") ", block (blockParts a), text " else ",
                  block (blockParts b)])
    | ECase (e, rules) =>
        let
          val scrutinee =
            case e of
              ETuple (first :: second :: more) => join (", ", SmlList.map exp (first :: second :: more))
            | _ => exp e
        in
          (0.0, cat (cats [text "match(", scrutinee, text ") "], arms rules))
        end
    | EFn [(p, body)] =>
        if paramOk p then (0.0, cats [params p, text " => ", lambdaBody body])
        else (0.0, cat (text "match ", arms [(p, body)]))
    | EFn rules => (0.0, cat (text "match ", arms rules))

  and exp = fn e => let val (_, d) = expL e in d end

  (* Application is always an explicit call; a tuple argument becomes the argument list. *)
  and call = fn (f, a) =>
    let
      val args =
        case a of
          ETuple [] => text "()"
        | ETuple es => group ("(", ",", ")", SmlList.map exp es)
        | _ => cats [text "(", exp a, text ")"]
    in
      (9.0, cat (parenAt (9.0, expL f), args))
    end

  (* A curried lambda chains without braces: (a) => (b) => { e }. *)
  and lambdaBody = fn
      EFn [(p, body)] =>
        if paramOk p then cats [params p, text " => ", lambdaBody body] else block ([], [EFn [(p, body)]])
    | e => block (blockParts e)

  and arms = fn rules =>
    let
      val arm = fn (p, e) => cats [pat (true, false, p), text " => ", block (blockParts e)]
      val count = Num.List.length rules
      val rec go = fn
          (_, []) => []
        | (i, r :: rest) => (if i < count - 1.0 then cat (arm r, text ",") else arm r) :: go (i + 1.0, rest)
    in
      stack [text "{", indent (2.0, stack (go (0.0, rules))), text "}"]
    end

  (* `{ decs; e1; ...; en }`, on one line when it is a single short expression. *)
  and block = fn (ds, es) =>
    let
      val count = Num.List.length es
      val rec exps = fn
          (_, []) => []
        | (i, e :: rest) => (if i < count - 1.0 then cat (exp e, text ";") else exp e) :: exps (i + 1.0, rest)
      val items = SmlList.map (fn d => dec ([], d)) ds @ exps (0.0, es)
    in
      case items of
        [single] =>
          if SmlList.null ds andalso fits single andalso Num.String.size (valOf (flat single)) <= 60.0
          then cats [text "{ ", single, text " }"]
          else stack [text "{", indent (2.0, single), text "}"]
      | _ => stack [text "{", indent (2.0, stack items), text "}"]
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Declarations. `structures` lists the program's structures, which become files. *)

  and binding = fn
      (PTyped (p, t), e) => cats [pat (false, true, p), text ": ", ty t, text " = ", exp e]
    | (p, e) => cats [pat (false, true, p), text " = ", exp e]

  and andGroup = fn (keyword, bindings) =>
    case bindings of
      [] => keyword
    | first :: rest =>
        let val lines = cat (keyword, first) :: SmlList.map (fn b => cat (text "and ", b)) rest in
          cat (stack lines, text ";")
        end

  and dec = fn (structures, d) =>
    case d of
      DVal (p, [], plain, []) => andGroup (atom (p, "let "), SmlList.map binding plain)
    | DVal (p, [], [], recs) => andGroup (atom (p, "let rec "), SmlList.map binding recs)
    | DVal _ => fallback d
    | DType (p, [(vs, tycon, TyRecord fields)]) =>
        cats [atom (p, "record "), text (capitalize tycon ^ typeParams vs ^ " = "),
              group ("{", ",", "}", SmlList.map (fn (l, t) => cats [text (l ^ ": "), ty t]) fields),
              text ";"]
    | DType (p, binds) =>
        if SmlList.exists (fn (_, _, t) => case t of TyRecord _ => true | _ => false) binds
        then fallback d
        else
          andGroup (atom (p, "type "),
                    SmlList.map (fn (vs, tycon, t) => cats [text (capitalize tycon ^ typeParams vs ^ " = "), ty t])
                      binds)
    | DDatatype (p, binds) =>
        let
          val con = fn
              (cp, c, NONE) => atom (cp, c)
            | (cp, c, SOME (TyTuple ts)) => cats [atom (cp, c), text "<", join (", ", SmlList.map ty ts), text ">"]
            | (cp, c, SOME t) => cats [atom (cp, c), text "<", ty t, text ">"]
          val bind = fn (vs, tycon, cons) =>
            let
              val head = text (capitalize tycon ^ typeParams vs ^ " =")
              val docs = SmlList.map con cons
              val oneLine =
                case docs of
                  [single] => cats [head, text " | ", single]
                | _ => cats [head, text " ", join (" | ", docs)]
            in
              if fits oneLine then oneLine
              else stack [head, indent (2.0, stack (SmlList.map (fn c => cat (text "| ", c)) docs))]
            end
        in
          andGroup (atom (p, "type "), SmlList.map bind binds)
        end
    | DOpen (p, ids) =>
        if SmlList.all (fn id => SmlList.exists (fn s => [s] = id) structures) ids
        then stack (SmlList.map (fn id => atom (p, "from \"./" ^ fileName (dotted ([], List.last id))
                                               ^ "\" import *;")) ids)
        else fallback d

  (* A declaration with no Workman form, in SML syntax and ended by `;` so that WmParse can
     find its extent. *)
  and fallback = fn d => cat (SmlPrint.dec d, text ";")

  (* `WmPrint` is in `wm_print.wm`. *)
  and fileName = fn name =>
    let
      val rec go = fn
          ([], _) => []
        | (c :: rest, first) =>
            if SubsetChar.isUpper c andalso not first
            then #"_" :: SubsetChar.toLower c :: go (rest, false)
            else SubsetChar.toLower c :: go (rest, false)
    in
      String.implode (go (String.explode name, true)) ^ ".wm"
    end

  val topdec = fn (structures, td) =>
    case td of
      TopDecs sds =>
        stack (SmlList.map (fn
                  SDec d => dec (structures, d)
                | SStructure (_, binds) =>
                    stack (SmlList.map (fn (_, ds) => stack (SmlList.map (fn d => dec (structures, d)) ds)) binds))
                sds)
    | TopExp (_, e) => cat (exp e, text ";")

  (* Comment lines in Workman syntax: `//` for one line, `/* */` for several. *)
  val commentStyle = fn
      [single] => ["// " ^ trim single]
    | lines =>
        let val n = Num.List.length lines in
          Num.List.tabulate (n, fn i =>
            (if Real.== (i, 0.0) then "/*" else "") ^ Num.List.nth (lines, i) ^ (if Real.== (i, n - 1.0) then "*/" else ""))
        end

end
