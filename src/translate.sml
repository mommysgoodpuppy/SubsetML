(* @subsetml
from "./syntax.sml" import * as Syntax;
from "./sml_list.sml" import * as SmlList;
from "./compiler_text.sml" import * as CompilerText;
from "./subset_char.sml" import * as SubsetChar;
from "./unify.sml" import * as Unify;
from "./types.sml" import * as Types;
from "./doc.sml" import * as Doc;
from "./wm_print.sml" import * as WmPrint;
from "./basis.sml" import * as Basis;
from "./elab.sml" import * as Elab;
from "./subset_string.sml" import * as SubsetString;
from "./backend_names.sml" import * as BackendNames;
from "./env.sml" import * as Env;
from "./wm_lexer.sml" import * as WmLexer;
from "./sml_print.sml" import * as SmlPrint;
from "./wm_parse.sml" import * as WmParse;
*)

(* Whole-file translation. By spec M1 a file has at most one structure, so each SubsetML file
   becomes one Workman module: `structure FooBar` in foo_bar.sml becomes foo_bar.wm, and the
   file's other top-level declarations join the module. *)
structure Translate = struct

  open Syntax

  (* --------------------------------------------------------------------------------------- *)
  (* The structures a phrase refers to: the first qualifier of each long identifier. *)

  val head = fn
      [] => []
    | q :: _ => [q]

  val concatMap = fn (f, xs) => SmlList.concat (SmlList.map f xs)

  val rec tyQuals = fn
      TyVar _ => []
    | TyCon (args, (qs, _)) => head qs @ concatMap (tyQuals, args)
    | TyTuple ts => concatMap (tyQuals, ts)
    | TyArrow (a, b) => tyQuals a @ tyQuals b
    | TyRecord fields => concatMap (fn (_, t) => tyQuals t, fields)

  val rec patQuals = fn
      PWild => []
    | PScon (_, _) => []
    | PId (_, (qs, _)) => head qs
    | PPinned (_, (qs, _)) => head qs
    | PRecord (_, fields) => concatMap (fn (_, p) => patQuals p, fields)
    | PTuple ps => concatMap (patQuals, ps)
    | PList ps => concatMap (patQuals, ps)
    | PApp (_, (qs, _), p) => head qs @ patQuals p
    | PTyped (p, t) => patQuals p @ tyQuals t

  val rec expQuals = fn
      EScon (_, _) => []
    | EId (_, (qs, _)) => head qs
    | ERecord (_, fields) => concatMap (fn (_, e) => expQuals e, fields)
    | ESelect (_, _) => []
    | ECopy (_, source, target, t) => expQuals source @ expQuals target @ tyQuals t
    | ETuple es => concatMap (expQuals, es)
    | EList es => concatMap (expQuals, es)
    | ESeq es => concatMap (expQuals, es)
    | ELet (ds, es) => concatMap (decQuals, ds) @ concatMap (expQuals, es)
    | EApp (f, a) => expQuals f @ expQuals a
    | ETyped (e, t) => expQuals e @ tyQuals t
    | EAndalso (a, b) => expQuals a @ expQuals b
    | EOrelse (a, b) => expQuals a @ expQuals b
    | EIf (c, a, b) => expQuals c @ expQuals a @ expQuals b
    | ECase (e, rules) => expQuals e @ ruleQuals rules
    | EFn rules => ruleQuals rules

  and ruleQuals = fn rules => concatMap (fn (p, e) => patQuals p @ expQuals e, rules)

  and decQuals = fn
      DVal (_, _, plain, recs) => ruleQuals (plain @ recs)
    | DType (_, binds) => concatMap (fn (_, _, t) => tyQuals t, binds)
    | DDatatype (_, binds) =>
        concatMap (fn (_, _, cons) =>
                     concatMap (fn (_, _, NONE) => [] | (_, _, SOME t) => tyQuals t, cons), binds)
    | DOpen (_, ids) => concatMap (head, ids)

  val decPos = fn
      DVal (p, _, _, _) => p
    | DType (p, _) => p
    | DDatatype (p, _) => p
    | DOpen (p, _) => p

  (* --------------------------------------------------------------------------------------- *)
  (* Dropping a qualifier. Outside its structure, `Main.main` refers to a binding of the same
     Workman module, where it is plain `main`. *)

  val unqualify = fn (self, id) =>
    case id of
      (q :: rest, x) => if q = self then (rest, x) else id
    | _ => id

  val rec tyStrip = fn (self, t) =>
    case t of
      TyVar _ => t
    | TyCon (args, id) => TyCon (SmlList.map (fn a => tyStrip (self, a)) args, unqualify (self, id))
    | TyTuple ts => TyTuple (SmlList.map (fn a => tyStrip (self, a)) ts)
    | TyArrow (a, b) => TyArrow (tyStrip (self, a), tyStrip (self, b))
    | TyRecord fields => TyRecord (SmlList.map (fn (l, a) => (l, tyStrip (self, a))) fields)

  val rec patStrip = fn (self, p) =>
    let val go = fn q => patStrip (self, q) in
      case p of
        PId (pos, id) => PId (pos, unqualify (self, id))
      | PRecord (pos, fields) => PRecord (pos, SmlList.map (fn (l, q) => (l, go q)) fields)
      | PTuple ps => PTuple (SmlList.map go ps)
      | PList ps => PList (SmlList.map go ps)
      | PApp (pos, id, q) => PApp (pos, unqualify (self, id), go q)
      | PTyped (q, t) => PTyped (go q, tyStrip (self, t))
      | _ => p
    end

  val rec expStrip = fn (self, e) =>
    let
      val go = fn x => expStrip (self, x)
      val rules = fn rs => SmlList.map (fn (p, x) => (patStrip (self, p), go x)) rs
    in
      case e of
        EId (pos, id) => EId (pos, unqualify (self, id))
      | ERecord (pos, fields) => ERecord (pos, SmlList.map (fn (l, x) => (l, go x)) fields)
      | ETuple es => ETuple (SmlList.map go es)
      | EList es => EList (SmlList.map go es)
      | ESeq es => ESeq (SmlList.map go es)
      | ELet (ds, es) => ELet (SmlList.map (fn d => decStrip (self, d)) ds, SmlList.map go es)
      | EApp (f, a) => EApp (go f, go a)
      | ETyped (x, t) => ETyped (go x, tyStrip (self, t))
      | ECopy (p, source, target, t) => ECopy (p, go source, go target, tyStrip (self, t))
      | EAndalso (a, b) => EAndalso (go a, go b)
      | EOrelse (a, b) => EOrelse (go a, go b)
      | EIf (c, a, b) => EIf (go c, go a, go b)
      | ECase (x, rs) => ECase (go x, rules rs)
      | EFn rs => EFn (rules rs)
      | _ => e
    end

  and decStrip = fn (self, d) =>
    let val rules = fn rs => SmlList.map (fn (p, x) => (patStrip (self, p), expStrip (self, x))) rs in
      case d of
        DVal (pos, vs, plain, recs) => DVal (pos, vs, rules plain, rules recs)
      | DType (pos, binds) => DType (pos, SmlList.map (fn (vs, n, t) => (vs, n, tyStrip (self, t))) binds)
      | DDatatype (pos, binds) =>
          DDatatype (pos, SmlList.map (fn (vs, n, cons) =>
            (vs, n, SmlList.map (fn (cp, c, NONE) => (cp, c, NONE)
                               | (cp, c, SOME t) => (cp, c, SOME (tyStrip (self, t)))) cons)) binds)
      | DOpen (_, _) => d
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Coding conventions (docs/conventions.md). Breaking one gives a warning, because the
     Workman output would be invalid or mean something else. *)

  (* Workman keywords that SML treats as ordinary identifiers. *)
  val wmKeywords = ["match", "record", "from", "import", "void"]

  val isUpper = fn s => CompilerText.firstIs (s, SubsetChar.isUpper)

  (* Every identifier written in a phrase, with the nearest known position. *)
  val rec patNames = fn (pos, p) =>
    case p of
      PId (q, (_, x)) => [(q, x)]
    | PRecord (q, fields) => concatMap (fn (l, f) => (q, l) :: patNames (q, f), fields)
    | PTuple ps => concatMap (fn f => patNames (pos, f), ps)
    | PList ps => concatMap (fn f => patNames (pos, f), ps)
    | PApp (q, (_, c), f) => (q, c) :: patNames (q, f)
    | PTyped (f, _) => patNames (pos, f)
    | _ => []

  val rec expNames = fn (pos, e) =>
    let val go = fn x => expNames (pos, x) in
      case e of
        EId (q, (_, x)) => [(q, x)]
      | ERecord (q, fields) => concatMap (fn (l, x) => (q, l) :: expNames (q, x), fields)
      | ESelect (q, l) => [(q, l)]
      | ECopy (_, source, target, _) => go source @ go target
      | ETuple es => concatMap (go, es)
      | EList es => concatMap (go, es)
      | ESeq es => concatMap (go, es)
      | ELet (ds, es) => concatMap (decNames, ds) @ concatMap (go, es)
      | EApp (f, a) => go f @ go a
      | ETyped (x, _) => go x
      | EAndalso (a, b) => go a @ go b
      | EOrelse (a, b) => go a @ go b
      | EIf (c, a, b) => go c @ go a @ go b
      | ECase (x, rules) => go x @ ruleNames (pos, rules)
      | EFn rules => ruleNames (pos, rules)
      | EScon (_, _) => []
    end

  and ruleNames = fn (pos, rules) => concatMap (fn (p, e) => patNames (pos, p) @ expNames (pos, e), rules)

  and decNames = fn
      DVal (pos, _, plain, recs) => ruleNames (pos, plain @ recs)
    | DType (pos, binds) => SmlList.map (fn (_, tycon, _) => (pos, tycon)) binds
    | DDatatype (pos, binds) =>
        concatMap (fn (_, tycon, cons) => (pos, tycon) :: SmlList.map (fn (cp, c, _) => (cp, c)) cons, binds)
    | DOpen (_, _) => []

  (* Warnings for one module's declarations and expressions. *)
  val conventionWarnings = fn (decs, exps) =>
    let
      val keyword = fn (pos, x) =>
        if SmlList.exists (fn k => k = x) wmKeywords
        then [(pos, "`" ^ x ^ "` is a Workman keyword; the translation will not parse")]
        else []
      val casing = fn
          DType (pos, binds) =>
            concatMap (fn (_, tycon, _) =>
                         if isUpper tycon then [(pos, "type `" ^ tycon ^ "` should start lowercase")] else [],
                       binds)
        | DDatatype (pos, binds) =>
            concatMap (fn (_, tycon, cons) =>
                         (if isUpper tycon then [(pos, "type `" ^ tycon ^ "` should start lowercase")] else [])
                         @ concatMap (fn (cp, c, _) =>
                                        if isUpper c then []
                                        else [(cp, "constructor `" ^ c ^ "` should start uppercase")], cons),
                       binds)
        | _ => []
    in
      concatMap (keyword, concatMap (decNames, decs) @ concatMap (fn e => expNames (0, e), exps))
      @ concatMap (casing, decs)
    end

  val distinct = fn xs =>
    SmlList.foldl (fn (x, acc) => if SmlList.exists (fn y => y = x) acc then acc else acc @ [x]) [] xs

  (* --------------------------------------------------------------------------------------- *)
  (* Files *)

  (* The file name without directory and extension. *)
  val baseName = fn path =>
    let
      val file =
        case SmlList.rev (CompilerText.fields (path, fn c => c = #"/")) of
          last :: _ => last
        | [] => path
    in
      if CompilerText.isSuffix (file, ".sml") then CompilerText.slice (file, 0, CompilerText.size file - 4) else file
    end

  (* The file's structure name, or "" when it has none. *)
  val structureOf = fn prog =>
    concatMap (fn
        TopDecs sds => concatMap (fn SStructure (_, binds) => SmlList.map (fn (name, _) => name) binds | SDec _ => [], sds)
      | TopExp (_, _) => [], prog)

  datatype result =
      Output of string * string * (pos * string) list   (* file name, contents, warnings *)
    | TranslateError of string

  (* The file as one module: its structure's name ("" if none), and its phrases in source
     order, with the structure's declarations in place and other phrases unqualified. *)
  val module = fn prog =>
    let
      val self =
        case structureOf prog of
          name :: _ => name
        | [] => ""
      val phrases =
        concatMap (fn
            TopDecs sds =>
              concatMap (fn
                  SStructure (_, binds) => concatMap (fn (_, ds) => SmlList.map (fn d => TopDecs [SDec d]) ds, binds)
                | SDec d => [TopDecs [SDec (decStrip (self, d))]], sds)
          | TopExp (p, e) => [TopDecs [SDec
              (DVal (p, [], [(PId (p, ([], "it")), expStrip (self, e))], []))]], prog)
    in
      (self, phrases)
    end

  (* The declarations and expressions of a module's phrases. *)
  val parts = fn phrases =>
    (concatMap (fn TopDecs sds => concatMap (fn SDec d => [d] | SStructure (_, _) => [], sds)
                 | TopExp (_, _) => [], phrases),
     concatMap (fn TopExp (_, e) => [e] | TopDecs _ => [], phrases))

  (* Declaration forms without a WM representation are errors, including inside functions.
     Expression compatibility operators remain supported independently of declarations. *)
  val declarationGaps = fn (structures, prog) =>
    let
      val rec expressions = fn es => concatMap (expression, es)
      and rules = fn rs => expressions (SmlList.map (fn (_, e) => e) rs) @ concatMap (fn (p, _) => patterns p, rs)
      and expression = fn e => case e of
          EScon _ => [] | EId _ => [] | ESelect _ => []
        | ERecord (_, fields) => expressions (SmlList.map (fn (_, e) => e) fields)
        | ETuple es => expressions es | EList es => expressions es | ESeq es => expressions es
        | ELet (ds, es) => concatMap (declaration, ds) @ expressions es
        | EApp (a, b) => expressions [a, b] | ETyped (e, _) => expression e
        | EAndalso (a, b) => expressions [a, b] | EOrelse (a, b) => expressions [a, b]
        | EIf (a, b, c) => expressions [a, b, c]
        | ECase (e, rs) => expression e @ rules rs | EFn rs => rules rs
        | ECopy (_, a, b, _) => expressions [a, b]
      and patterns = fn p => case p of
          PTyped (p, _) => patterns p
        | PRecord (_, fs) => concatMap (fn (_, p) => patterns p, fs)
        | PTuple ps => concatMap (patterns, ps) | PList ps => concatMap (patterns, ps)
        | PApp (_, _, p) => patterns p | _ => []
      and declaration = fn d => case d of
          DVal (_, variables, plain, recs) =>
            (if not (SmlList.null variables) then ["explicit val type variables"]
             else (if not (SmlList.null plain) andalso not (SmlList.null recs)
             then ["mixed plain/recursive val bindings"] else [])) @ rules (plain @ recs)
        | DType (_, binds) =>
            (if (case binds of [] => false | [_] => false | _ => true) andalso
              SmlList.exists (fn (_, _, t) => case t of TyRecord _ => true | _ => false) binds
            then ["type groups containing records"] else [])
        | DDatatype _ => []
        | DOpen (_, ids) => if SmlList.all (fn id => SmlList.exists (fn s => [s] = id) structures) ids
            then [] else ["open of a non-project structure"]
      val top = fn td => case td of
          TopExp (_, e) => expression e
        | TopDecs ds => concatMap (fn SDec d => declaration d
            | SStructure (_, binds) => concatMap (fn (_, ds) => concatMap (declaration, ds), binds), ds)
    in concatMap (top, prog) end

  (* SML closes an unresolved numeric class to int; Workman closes it to Number. A program that
     relies on either default would change meaning in translation, so it must annotate. An int
     constant is never such a site: it is int in SML and printed as an I32 ascription. *)
  val defaultedSite = fn st =>
    let
      val rec unresolved = fn t => case Unify.prune (st, t) of
          Types.TCon (_, ts) => SmlList.exists unresolved ts
        | Types.TVar v => (case Unify.lookup (st, v) of
            Unify.Free (Types.KClass _, _) => true
          | _ => false)
        | Types.TArrow (a, b) => unresolved a orelse unresolved b
        | Types.TRecord fs => SmlList.exists (fn (_, t) => unresolved t) fs
        | _ => false
      val Unify.State (_, _, _, _, sites) = st
    in
      case sites of NONE => NONE | SOME xs =>
        (case SmlList.mapPartial (fn Unify.Defaulted pos => SOME pos
                                   | Unify.Operand (pos, t) => if unresolved t then SOME pos else NONE) xs of
           [] => NONE
         | pos :: _ => SOME pos)
    end

  val defaultedMessage = "a numeric operation whose type only a default decides (SML int, Workman Number); annotate it as int or real"

  val wmNumbers = fn st => case defaultedSite st of
    NONE => Unify.Ok ((), st)
  | SOME pos => Unify.Err (defaultedMessage, pos)

  (* Translates one parsed file. `structures` names every structure of the program. *)
  val toWm = fn (structures, path, src, prog, comments) =>
    let
      val (self, phrases) = module prog
      val (decs, exps) = parts phrases
      val used = distinct (concatMap (decQuals, decs) @ concatMap (expQuals, exps))
      val start =
        case prog of
          TopDecs (SStructure (p, _) :: _) :: _ => p
        | _ => 0
      val imports =
        SmlList.map (fn q => Doc.atom (start, "from \"./" ^ WmPrint.fileName q ^ "\" import * as " ^ q ^ ";"))
          (SmlList.filter (fn q => q <> self andalso SmlList.exists (fn s => s = q) structures) used)
      (* Reject a numeric default when the file's standalone environment can be resolved. *)
      val defaulted = case Basis.initial of Unify.Err _ => false | Unify.Ok (basis, _) =>
        (case Elab.program (basis, prog, Unify.lenient) of Unify.Err _ => false
         | Unify.Ok (_, st) => case defaultedSite st of SOME _ => true | NONE => false)
      val gaps = declarationGaps (structures, phrases) @
        (if defaulted then [defaultedMessage] else [])
      val doc = if SmlList.null gaps then Doc.stack (SmlList.map (fn td => WmPrint.topdec (structures, td)) phrases) else Doc.text ""
      val body =
        case imports of
          [] => doc
        | _ => Doc.stack [Doc.stack imports, Doc.text "", doc]
      val expected = WmPrint.fileName self
    in
      if not (SmlList.null gaps) then
        TranslateError (path ^ ": unsupported WM translation: " ^ SubsetString.concatWith (gaps, ", ") ^
          "; embedded SML declarations are not supported")
      else (if self <> "" andalso expected <> baseName path ^ ".wm" then
        TranslateError (path ^ ": structure " ^ self ^ " must be in a file named "
                        ^ CompilerText.slice (expected, 0, CompilerText.size expected - 3) ^ ".sml")
      else
        Output (baseName path ^ ".wm", Doc.render (src, comments, WmPrint.commentStyle, body),
                conventionWarnings (decs, exps)))
    end

  (* Traverse expressions without changing source positions or declaration layout. *)
  val rec mapExp = fn (f, e) =>
    let
      val go = fn x => mapExp (f, x)
      val rules = fn rs => SmlList.map (fn (p, x) => (p, go x)) rs
    in
      f (case e of
           ERecord (p, fs) => ERecord (p, SmlList.map (fn (l, x) => (l, go x)) fs)
         | ETuple es => ETuple (SmlList.map go es)
         | EList es => EList (SmlList.map go es)
         | ESeq es => ESeq (SmlList.map go es)
         | ELet (ds, es) => ELet (SmlList.map (fn d => mapDec (f, d)) ds, SmlList.map go es)
         | EApp (a, b) => EApp (go a, go b)
         | ETyped (x, t) => ETyped (go x, t)
         | ECopy (p, source, target, t) => ECopy (p, go source, go target, t)
         | EAndalso (a, b) => EAndalso (go a, go b)
         | EOrelse (a, b) => EOrelse (go a, go b)
         | EIf (c, a, b) => EIf (go c, go a, go b)
         | ECase (x, rs) => ECase (go x, rules rs)
         | EFn rs => EFn (rules rs)
         | _ => e)
    end

  and mapDec = fn (f, d) =>
    case d of
      DVal (p, vs, plain, recs) =>
        let val rules = fn rs => SmlList.map (fn (pat, e) => (pat, mapExp (f, e))) rs in
          DVal (p, vs, rules plain, rules recs)
        end
    | _ => d

  val mapProgram = fn (f, prog) =>
    SmlList.map (fn
        TopDecs sds => TopDecs (SmlList.map (fn
            SDec d => SDec (mapDec (f, d))
          | SStructure (p, binds) => SStructure (p, SmlList.map (fn (n, ds) =>
              (n, SmlList.map (fn d => mapDec (f, d)) ds)) binds)) sds)
      | TopExp (p, e) => TopExp (p, mapExp (f, e))) prog

  (* Native source spelling is a backend mapping, not a change to WM names or FFI keys.
     One project-wide prefix is absent from every input byte string. *)
  val keywordPrefix = BackendNames.prefix

  (* Compatibility entry: the source-list backend uses project-wide binding resolution. *)
  val keywordProgram = fn (prefix, prog) =>
    let val (prog, _, _) = BackendNames.module ("", [], prog, BackendNames.Supply (prefix, 0, []))
    in prog end

  (* Workman equality is ambiguous until elaboration. Only a scalar real comparison is
     rewritten; a second, strict elaboration rejects every remaining invalid SML equality. *)
  val realEquality = fn (st, prog) =>
    let
      val Unify.State (_, _, _, _, sites) = st
      val positions = SmlList.mapPartial (fn
          Unify.Operand (p, t) => (case Unify.prune (st, t) of
             Types.TCon (n, []) => if Unify.sameName (n, Types.realName) then SOME p else NONE
           | _ => NONE)
        | Unify.Defaulted _ => NONE) (case sites of SOME xs => xs | NONE => [])
      val rewrite = fn e =>
        case e of
          EApp (EId (p, ([], opr)), a) =>
            if (opr = "=" orelse opr = "<>") andalso SmlList.exists (fn q => (p = q)) positions
            then EApp (EId (p, (["Real"], if opr = "=" then "==" else "!=")), a)
            else e
        | _ => e
    in
      mapProgram (rewrite, prog)
    end

  (* WM can generalize a pure function-field alias; SML selector applications cannot.
     Probe in the declaration's actual environment, then wrap only a known function.
     The probe state is discarded: the emitted expression is elaborated normally, so
     captured monomorphic variables keep their levels and ordinary partial applications
     retain their source restriction. This first pass handles module-level bindings. *)
  val portableValues = fn (env, prog, st) =>
    let
      val used = concatMap (fn TopDecs sds => concatMap (fn SDec d => decNames d
        | SStructure (_, bs) => concatMap (fn (_, ds) => concatMap (decNames, ds), bs), sds)
        | TopExp (p, e) => expNames (p, e), prog)
      val fresh = fn n => BackendNames.avoid (SmlList.map (fn (_, x) => x) used, n)
      val rec options = fn xs =>
        case xs of [] => SOME [] | NONE :: _ => NONE
        | SOME x :: rest => (case options rest of SOME xs => SOME (x :: xs) | NONE => NONE)
      (* Find a visible nominal constructor, including imported datatypes. Only identity
         aliases qualify: an alias with permuted/fixed arguments is not a spelling for it. *)
      val typeName = fn (env, nominal) =>
        let
          val rec identity = fn (i, args) => case args of [] => true
            | Types.TGen j :: rest => (i = j) andalso identity (i + 1, rest)
            | _ => false
          val rec find = fn (Env.Env (structures, types, _), path) =>
            let
              val rec localType = fn (types, seen) => case types of [] => NONE
                | (n, Env.TyStr (arity, body, _)) :: rest =>
                    if SmlList.exists (fn x => x = n) seen then localType (rest, seen)
                    else (case body of Types.TCon (name, args) =>
                      if Unify.sameName (name, nominal) andalso (arity = Types.arityOf nominal)
                        andalso identity (0, args) then SOME (path, n)
                      else localType (rest, n :: seen)
                    | _ => localType (rest, n :: seen))
              val rec imported = fn (structures, seen) => case structures of [] => NONE
                | (n, (body, _)) :: rest =>
                    if SmlList.exists (fn x => x = n) seen then imported (rest, seen)
                    else (case find (body, path @ [n]) of SOME id => SOME id
                      | NONE => imported (rest, n :: seen))
            in case localType (types, []) of SOME id => SOME id | NONE => imported (structures, []) end
        in if Types.stampOf nominal < Types.firstStamp then SOME ([], Types.nameOf nominal)
           else find (env, []) end
      val copy = fn (env, p, source, target, layout, st) =>
        case layout of TyCon (parameters, id) =>
          let val variables = concatMap (fn TyVar v => [v] | _ => [], parameters) in
            Unify.bind (Elab.exp ((env, 1, []), source, st)) (fn sourceType => fn probe =>
              Unify.bind (Elab.mapRes (fn (v, probe) =>
                let val (t, probe) = Unify.fresh (probe, Types.KPlain, 1)
                in Unify.Ok ((v, t), probe) end, variables, probe)) (fn arguments => fn probe =>
                Unify.bind (Elab.elabTy (env, fn v => Env.assoc (v, arguments), p, layout, probe))
                  (fn layoutType => fn probe =>
                    Unify.bind (Elab.unifyAt (probe, p, "copied layout", layoutType, sourceType)) (fn _ => fn probe =>
                      Unify.bind (Elab.closeDeclaration (0, probe)) (fn _ => fn probe =>
                        let
                          val rec syntaxType = fn t => case Unify.prune (probe, t) of
                              Types.TVar v => (case Unify.lookup (probe, v) of
                                Unify.Free (kind, level) => if level <= 0 then NONE
                                  else (case kind of Types.KClass _ => NONE | _ =>
                                    SOME (TyVar ((case kind of Types.KEq => "''" | _ => "'") ^
                                      fresh ("subsetmlCopy" ^ CompilerText.natural p ^ "Variable" ^ CompilerText.natural v))))
                              | _ => NONE)
                            | Types.TRigid _ => NONE
                            | Types.TGen _ => NONE
                            | Types.TArrow (a, b) => (case (syntaxType a, syntaxType b) of
                                (SOME a, SOME b) => SOME (TyArrow (a, b)) | _ => NONE)
                            | Types.TCon (n, args) => (case (typeName (env, n), options (SmlList.map syntaxType args)) of
                                (SOME id, SOME args) => SOME (TyCon (args, id)) | _ => NONE)
                            | Types.TRecord [] => SOME (TyCon ([], ([], "unit")))
                            | Types.TRecord fields => (case Types.tupleComponents fields of
                                SOME types => (case options (SmlList.map syntaxType types) of
                                  SOME types => SOME (TyTuple types) | NONE => NONE)
                              | NONE => NONE)
                          val inferred = options (SmlList.map (fn (_, t) => syntaxType t) arguments)
                          val expanded = case target of ERecord (q, fields) =>
                              ERecord (q, SmlList.map (fn (label, value) =>
                                let val argument = fresh ("subsetmlCopy" ^ CompilerText.natural p ^ "_" ^ label)
                                in (label, EFn [(PId (p, ([], argument)), EApp (value, EId (p, ([], argument))))]) end) fields)
                            | _ => target
                        in Unify.Ok ((case inferred of SOME args => ETyped (expanded, TyCon (args, id))
                          | NONE => source), st) end)))))
          end
        | _ => Unify.Ok (source, st)
      val expression = fn (env, p, e, st) =>
        case e of
          ECopy (p, source, target, layout) => copy (env, p, source, target, layout, st)
        |
          EApp (ESelect (_, _), EId (_, _)) =>
            Unify.bind (Elab.exp ((env, 1, []), e, st)) (fn t => fn probe =>
              Unify.bind (Elab.closeDeclaration (0, probe)) (fn _ => fn probe =>
                case Unify.prune (probe, t) of
                  Types.TArrow (_, _) =>
                    let val arg = fresh ("subsetmlAlias" ^ CompilerText.natural p)
                    in Unify.Ok (EFn [(PId (p, ([], arg)), EApp (e, EId (p, ([], arg))))], st) end
                | _ => Unify.Ok (e, st)))
        | _ => Unify.Ok (e, st)
      val declaration = fn (env, d, st) =>
        case d of
          DVal (p, vs, [(pattern, e)], []) =>
            (case pattern of
               PId (_, ([], _)) => Unify.bind (expression (env, p, e, st)) (fn e => fn st =>
                 Unify.Ok (DVal (p, vs, [(pattern, e)], []), st))
             | _ => Unify.Ok (d, st))
        | _ => Unify.Ok (d, st)
      val rec declarations = fn (env, ds, st) =>
        case ds of [] => Unify.Ok ((Env.empty, []), st)
        | d :: rest => Unify.bind (declaration (env, d, st)) (fn d => fn st =>
            Unify.bind (Elab.dec ((env, 0, []), d, st)) (fn delta => fn st =>
              Unify.bind (declarations (Env.plus (env, delta), rest, st)) (fn (more, rest) => fn st =>
                Unify.Ok ((Env.plus (delta, more), d :: rest), st))))
      val structureDec = fn (env, sd, st) =>
        case sd of SDec d => Unify.bind (declaration (env, d, st)) (fn d => fn st =>
          Unify.bind (Elab.dec ((env, 0, []), d, st)) (fn delta => fn st => Unify.Ok ((delta, SDec d), st)))
        | SStructure (p, bs) =>
            Unify.bind (Elab.foldRes (fn ((delta, output), (n, ds), st) =>
              Unify.bind (declarations (env, ds, st)) (fn (body, ds) => fn st =>
                Unify.Ok ((Env.plus (delta, Env.withStructure (n, body, false)), output @ [(n, ds)]), st)),
              (Env.empty, []), bs, st)) (fn (delta, bs) => fn st =>
                Unify.Ok ((delta, SStructure (p, bs)), st))
      val rec structures = fn (env, sds, st) =>
        case sds of [] => Unify.Ok ((Env.empty, []), st)
        | sd :: rest => Unify.bind (structureDec (env, sd, st)) (fn (delta, sd) => fn st =>
              Unify.bind (structures (Env.plus (env, delta), rest, st)) (fn (more, rest) => fn st =>
                Unify.Ok ((Env.plus (delta, more), sd :: rest), st)))
      val rec phrases = fn (env, prog, st) =>
        case prog of [] => Unify.Ok ((env, []), st)
        | td :: rest =>
            Unify.bind (case td of TopDecs sds =>
              Unify.bind (structures (env, sds, st)) (fn (delta, sds) => fn st =>
                Unify.Ok ((delta, TopDecs sds), st))
              | _ => Unify.bind (Elab.topdec (env, td, st)) (fn delta => fn st =>
                Unify.Ok ((delta, td), st))) (fn (delta, td) => fn st =>
                Unify.bind (phrases (Env.plus (env, delta), rest, st)) (fn (env, rest) => fn st =>
                  Unify.Ok ((env, td :: rest), st)))
    in phrases (env, prog, st) end

  (* Check dependencies before a module, regardless of the command-line order. Every
     recovery starts with its dependency closure, so unrelated input files remain independent. *)
  val recover = fn (modules, target) =>
    let
      val nameOfModule = fn (_, _, prog, _) =>
        case structureOf prog of n :: _ => n | [] => ""
      val rec decDeps = fn d =>
        case d of
          DOpen (_, ids) => concatMap (head, ids)
        | _ => decQuals d
      val deps = fn (_, _, prog, _) =>
        distinct (concatMap (fn
            TopDecs sds => concatMap (fn SDec d => decDeps d
              | SStructure (_, bs) => concatMap (fn (_, ds) => concatMap (decDeps, ds), bs), sds)
          | TopExp (_, e) => expQuals e, prog))
      val rec order = fn (item, visiting, done, acc) =>
        let val name = nameOfModule item in
          if SmlList.exists (fn n => n = name) done then Unify.Ok ((done, acc), Unify.initial)
          else (if SmlList.exists (fn n => n = name) visiting then
            Unify.Err ("cyclic module dependency involving " ^ name, 0)
          else
            let
              val needed = SmlList.filter (fn m => nameOfModule m <> name andalso
                SmlList.exists (fn n => n = nameOfModule m) (deps item)) modules
              val rec walk = fn
                  ([], done, acc) => Unify.Ok ((name :: done, acc @ [item]), Unify.initial)
                | (m :: rest, done, acc) =>
                    Unify.bind (order (m, name :: visiting, done, acc)) (fn (done, acc) => fn _ =>
                      walk (rest, done, acc))
            in walk (needed, done, acc) end)
        end
      val rec elaborate = fn
          (_, [], st, acc) => Unify.Ok (acc, st)
        | (env, (path, src, prog, comments) :: rest, st, acc) =>
            let val Unify.State (vars, next, sels, recs, _) = st in
              Unify.bind (portableValues (env, prog, Unify.State (vars, next, sels, recs, SOME [])))
                (fn (env, prog) => fn st => Unify.bind (wmNumbers st) (fn _ => fn st =>
                  elaborate (env, rest, st, acc @ [(path, src, realEquality (st, prog), comments)])))
            end
      val rec strict = fn
          (_, [], st) => Unify.Ok ((), st)
        | (env, (_, _, prog, _) :: rest, st) =>
            Unify.bind (Elab.program (env, prog, st)) (fn env => fn st => strict (env, rest, st))
    in
      Unify.bind (order (target, [], [], [])) (fn (_, ordered) => fn _ =>
        let
          val prefix = BackendNames.prefix (SmlList.map (fn (path, src, _, _) => (path, src)) ordered)
          val (planned, names) = BackendNames.project (prefix,
            SmlList.map (fn m => (nameOfModule m, deps m, m)) ordered)
          val ordered = SmlList.map (fn (_, _, m) => m) planned
        in case BackendNames.failure names of
          SOME (_, p, message) => Unify.Err (message, p)
        | NONE => Unify.bind Basis.initial (fn basis => fn _ =>
          Unify.bind (elaborate (basis, ordered, Unify.lenient, [])) (fn rewritten => fn _ =>
            Unify.bind (strict (basis, rewritten, Unify.initial)) (fn _ => fn st =>
              case SmlList.find (fn m => nameOfModule m = nameOfModule target) rewritten of
                SOME m => Unify.Ok (m, st)
              | NONE => Unify.Err ("missing translated module", 0)))) end)
    end

  (* Modules arrive in resolved dependency order. Each checker sees only direct imports;
     cache owned structure environments, never an importer's ambient environment. *)
  val recoverProjectWithRuntime = fn (runtime, modules) =>
    let
      val working = fn (basis, cache, dependencies) =>
        SmlList.foldl (fn (name, result) => Unify.bind result (fn env => fn st =>
          case SmlList.find (fn (key, _) => key = name) cache of
            NONE => Unify.Err ("missing resolved dependency " ^ name, 0)
          | SOME (_, body) => Unify.Ok (Env.plus (env, Env.withStructure (name, body, false)), st)))
          (Unify.Ok (basis, Unify.initial)) dependencies
      val own = fn (env, name) =>
        case Env.structureAt (env, [name]) of
          NONE => Unify.Err ("missing translated structure " ^ name, 0)
        | SOME (body, _) =>
            let val selected = case runtime of SOME key => key = name | NONE => false
                val valid = case Env.value (body, ([], "panic")) of
                  SOME (([Types.KPlain], Types.TArrow (Types.TCon (tn, []), Types.TGen index)), Env.SValue) =>
                    (Types.stampOf tn = Types.stampOf Types.stringName) andalso (index = 0)
                | _ => false
            in if selected andalso not valid then
                 Unify.Err ("panic runtime must export panic : string -> 'a", 0)
               else Unify.Ok (body, Unify.initial) end
      val rec rewrite = fn (basis, remaining, cache, st, acc) =>
        case remaining of
          [] => Unify.Ok (SmlList.rev acc, st)
        | (name, dependencies, (path, src, prog, cs)) :: rest =>
            Unify.bind (working (basis, cache, dependencies)) (fn env => fn _ =>
              let val Unify.State (vars, next, sels, recs, _) = st in
                Unify.bind (portableValues (env, prog, Unify.State (vars, next, sels, recs, SOME [])))
                  (fn (exports, rewritten) => fn next => Unify.bind (wmNumbers next) (fn _ => fn next =>
                    Unify.bind (own (exports, name)) (fn body => fn _ =>
                      rewrite (basis, rest, (name, body) :: cache, next,
                        (name, dependencies, (path, src, realEquality (next, rewritten), cs)) :: acc))))
              end)
      val rec strict = fn (basis, remaining, cache, st) =>
        case remaining of
          [] => Unify.Ok ((), st)
        | (name, dependencies, (_, _, prog, _)) :: rest =>
            Unify.bind (working (basis, cache, dependencies)) (fn env => fn _ =>
              Unify.bind (Elab.programExports (env, prog, st)) (fn exports => fn next =>
                Unify.bind (own (exports, name)) (fn body => fn _ =>
                  strict (basis, rest, (name, body) :: cache, next))))
    in
      Unify.bind Basis.initial (fn basis => fn _ =>
        Unify.bind (rewrite (basis, modules, [], Unify.lenient, [])) (fn rewritten => fn _ =>
          Unify.bind (strict (basis, rewritten, [], Unify.initial)) (fn _ => fn st =>
            Unify.Ok (SmlList.map (fn (_, _, m) => m) rewritten, st))))
    end

  val recoverProject = fn modules => recoverProjectWithRuntime (NONE, modules)

  (* A Workman module as SubsetML: its declarations become the structure named by the file. *)
  val fromWmNamed = fn (name, src, decs, exps, comments) =>
    let
      (* Imports disappear from the AST. Anchor the structure before them, so comments
         between an import and the first declaration stay inside the structure. *)
      val first =
        case WmLexer.lex src of
          WmLexer.Tokens ((WmLexer.WKey "from", p) :: _, _) => SOME p
        | _ => (case decs of d :: _ => SOME (decPos d) | [] => NONE)
      val structureLine =
        case first of
          SOME p => Doc.atom (p, "structure " ^ name ^ " = struct")
        | NONE => Doc.text ("structure " ^ name ^ " = struct")
      val structureDoc =
        Doc.stack [structureLine,
                   Doc.indent (2, Doc.stack (SmlList.map SmlPrint.dec decs)),
                   Doc.text "end"]
      val expDocs = SmlList.map (fn e => Doc.cat (SmlPrint.exp e, Doc.text ";")) exps
      val doc =
        case expDocs of
          [] => structureDoc
        | _ => Doc.stack (Doc.cat (structureDoc, Doc.text ";") :: expDocs)
    in
      Doc.render (src, comments, SmlPrint.commentStyle, doc)
    end

  val fromWm = fn (path, src, decs, exps, comments) =>
    fromWmNamed (WmParse.structureName path, src, decs, exps, comments)

  (* Reprints a parsed file as SubsetML. *)
  val toSml = fn (src, prog, comments) =>
    let
      (* A declaration phrase needs its `;` when an expression phrase follows (Definition §8). *)
      val rec phrases = fn
          [] => []
        | TopDecs sds :: (TopExp (pos, e) :: rest) =>
            Doc.cat (SmlPrint.topdec (TopDecs sds), Doc.text ";") :: phrases (TopExp (pos, e) :: rest)
        | td :: rest => SmlPrint.topdec td :: phrases rest
    in
      Doc.render (src, comments, SmlPrint.commentStyle, Doc.stack (phrases prog))
    end

end
