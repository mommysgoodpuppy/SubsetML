(* Whole-file translation. By spec M1 a file has at most one structure, so each SubsetML file
   becomes one Workman module: `structure FooBar` in foo_bar.sml becomes foo_bar.wm, and the
   file's other top-level declarations join the module. *)
structure Translate = struct

  open Syntax

  (* --------------------------------------------------------------------------------------- *)
  (* The structures a phrase refers to: the first qualifier of each long identifier. *)

  val head = fn
      [] => []
    | q :: ignored1 => [q]

  val concatMap = fn (f, xs) => SmlList.concat (SmlList.map f xs)

  val rec tyQuals = fn
      TyVar ignored2 => []
    | TyCon (args, (qs, ignored3)) => head qs @ concatMap (tyQuals, args)
    | TyTuple ts => concatMap (tyQuals, ts)
    | TyArrow (a, b) => tyQuals a @ tyQuals b
    | TyRecord fields => concatMap (fn (ignored4, t) => tyQuals t, fields)

  val rec patQuals = fn
      PWild => []
    | PScon (ignored5Field0, ignored5Field1) => []
    | PId (ignored6, (qs, ignored7)) => head qs
    | PRecord (ignored8, fields) => concatMap (fn (ignored9, p) => patQuals p, fields)
    | PTuple ps => concatMap (patQuals, ps)
    | PList ps => concatMap (patQuals, ps)
    | PApp (ignored10, (qs, ignored11), p) => head qs @ patQuals p
    | PTyped (p, t) => patQuals p @ tyQuals t

  val rec expQuals = fn
      EScon (ignored12Field0, ignored12Field1) => []
    | EId (ignored13, (qs, ignored14)) => head qs
    | ERecord (ignored15, fields) => concatMap (fn (ignored16, e) => expQuals e, fields)
    | ESelect (ignored17Field0, ignored17Field1) => []
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
      DVal (ignored18, ignored19, plain, recs) => ruleQuals (plain @ recs)
    | DType (ignored20, binds) => concatMap (fn (ignored21, ignored22, t) => tyQuals t, binds)
    | DDatatype (ignored23, binds) =>
        concatMap (fn (ignored24, ignored25, cons) =>
                     concatMap (fn (ignored26, ignored27, NONE) => [] | (ignored28, ignored29, SOME t) => tyQuals t, cons), binds)
    | DOpen (ignored30, ids) => concatMap (head, ids)

  val decPos = fn
      DVal (p, ignored31, ignored32, ignored33) => p
    | DType (p, ignored34) => p
    | DDatatype (p, ignored35) => p
    | DOpen (p, ignored36) => p

  (* --------------------------------------------------------------------------------------- *)
  (* Dropping a qualifier. Outside its structure, `Main.main` refers to a binding of the same
     Workman module, where it is plain `main`. *)

  val unqualify = fn (self, id) =>
    case id of
      (q :: rest, x) => if q = self then (rest, x) else id
    | ignored37 => id

  val rec tyStrip = fn (self, t) =>
    case t of
      TyVar ignored38 => t
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
      | ignored39 => p
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
      | EAndalso (a, b) => EAndalso (go a, go b)
      | EOrelse (a, b) => EOrelse (go a, go b)
      | EIf (c, a, b) => EIf (go c, go a, go b)
      | ECase (x, rs) => ECase (go x, rules rs)
      | EFn rs => EFn (rules rs)
      | ignored40 => e
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
      | DOpen (ignored41Field0, ignored41Field1) => d
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
      PId (q, (ignored42, x)) => [(q, x)]
    | PRecord (q, fields) => concatMap (fn (l, f) => (q, l) :: patNames (q, f), fields)
    | PTuple ps => concatMap (fn f => patNames (pos, f), ps)
    | PList ps => concatMap (fn f => patNames (pos, f), ps)
    | PApp (q, (ignored43, c), f) => (q, c) :: patNames (q, f)
    | PTyped (f, ignored44) => patNames (pos, f)
    | ignored45 => []

  val rec expNames = fn (pos, e) =>
    let val go = fn x => expNames (pos, x) in
      case e of
        EId (q, (ignored46, x)) => [(q, x)]
      | ERecord (q, fields) => concatMap (fn (l, x) => (q, l) :: expNames (q, x), fields)
      | ESelect (q, l) => [(q, l)]
      | ETuple es => concatMap (go, es)
      | EList es => concatMap (go, es)
      | ESeq es => concatMap (go, es)
      | ELet (ds, es) => concatMap (decNames, ds) @ concatMap (go, es)
      | EApp (f, a) => go f @ go a
      | ETyped (x, ignored47) => go x
      | EAndalso (a, b) => go a @ go b
      | EOrelse (a, b) => go a @ go b
      | EIf (c, a, b) => go c @ go a @ go b
      | ECase (x, rules) => go x @ ruleNames (pos, rules)
      | EFn rules => ruleNames (pos, rules)
      | EScon (ignored48Field0, ignored48Field1) => []
    end

  and ruleNames = fn (pos, rules) => concatMap (fn (p, e) => patNames (pos, p) @ expNames (pos, e), rules)

  and decNames = fn
      DVal (pos, ignored49, plain, recs) => ruleNames (pos, plain @ recs)
    | DType (pos, binds) => SmlList.map (fn (ignored50, tycon, ignored51) => (pos, tycon)) binds
    | DDatatype (pos, binds) =>
        concatMap (fn (ignored52, tycon, cons) => (pos, tycon) :: SmlList.map (fn (cp, c, ignored53) => (cp, c)) cons, binds)
    | DOpen (ignored54Field0, ignored54Field1) => []

  (* Warnings for one module's declarations and expressions. *)
  val conventionWarnings = fn (decs, exps) =>
    let
      val keyword = fn (pos, x) =>
        if SmlList.exists (fn k => k = x) wmKeywords
        then [(pos, "`" ^ x ^ "` is a Workman keyword; the translation will not parse")]
        else []
      val casing = fn
          DType (pos, binds) =>
            concatMap (fn (ignored55, tycon, ignored56) =>
                         if isUpper tycon then [(pos, "type `" ^ tycon ^ "` should start lowercase")] else [],
                       binds)
        | DDatatype (pos, binds) =>
            concatMap (fn (ignored57, tycon, cons) =>
                         (if isUpper tycon then [(pos, "type `" ^ tycon ^ "` should start lowercase")] else [])
                         @ concatMap (fn (cp, c, ignored58) =>
                                        if isUpper c then []
                                        else [(cp, "constructor `" ^ c ^ "` should start uppercase")], cons),
                       binds)
        | ignored59 => []
    in
      concatMap (keyword, concatMap (decNames, decs) @ concatMap (fn e => expNames (0.0, e), exps))
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
          last :: ignored60 => last
        | [] => path
    in
      if CompilerText.isSuffix (file, ".sml") then CompilerText.slice (file, 0.0, CompilerText.size file - 4.0) else file
    end

  (* The file's structure name, or "" when it has none. *)
  val structureOf = fn prog =>
    concatMap (fn
        TopDecs sds => concatMap (fn SStructure (ignored61, binds) => SmlList.map (fn (name, ignored62) => name) binds | SDec ignored63 => [], sds)
      | TopExp (ignored64Field0, ignored64Field1) => [], prog)

  datatype result =
      Output of string * string * (pos * string) list   (* file name, contents, warnings *)
    | TranslateError of string

  (* The file as one module: its structure's name ("" if none), and its phrases in source
     order, with the structure's declarations in place and other phrases unqualified. *)
  val module = fn prog =>
    let
      val self =
        case structureOf prog of
          name :: ignored65 => name
        | [] => ""
      val phrases =
        concatMap (fn
            TopDecs sds =>
              concatMap (fn
                  SStructure (ignored66, binds) => concatMap (fn (ignored67, ds) => SmlList.map (fn d => TopDecs [SDec d]) ds, binds)
                | SDec d => [TopDecs [SDec (decStrip (self, d))]], sds)
          | TopExp (p, e) => [TopDecs [SDec
              (DVal (p, [], [(PId (p, ([], "it")), expStrip (self, e))], []))]], prog)
    in
      (self, phrases)
    end

  (* The declarations and expressions of a module's phrases. *)
  val parts = fn phrases =>
    (concatMap (fn TopDecs sds => concatMap (fn SDec d => [d] | SStructure (ignored68Field0, ignored68Field1) => [], sds)
                 | TopExp (ignored69Field0, ignored69Field1) => [], phrases),
     concatMap (fn TopExp (ignored70, e) => [e] | TopDecs ignored71 => [], phrases))

  (* Translates one parsed file. `structures` names every structure of the program. *)
  val toWm = fn (structures, path, src, prog, comments) =>
    let
      val (self, phrases) = module prog
      val (decs, exps) = parts phrases
      val used = distinct (concatMap (decQuals, decs) @ concatMap (expQuals, exps))
      val start =
        case prog of
          TopDecs (SStructure (p, ignored72) :: ignored73) :: ignored74 => p
        | ignored75 => 0.0
      val imports =
        SmlList.map (fn q => Doc.atom (start, "from \"./" ^ WmPrint.fileName q ^ "\" import * as " ^ q ^ ";"))
          (SmlList.filter (fn q => q <> self andalso SmlList.exists (fn s => s = q) structures) used)
      val doc = Doc.stack (SmlList.map (fn td => WmPrint.topdec (structures, td)) phrases)
      val body =
        case imports of
          [] => doc
        | ignored76 => Doc.stack [Doc.stack imports, Doc.text "", doc]
      val expected = WmPrint.fileName self
    in
      if self <> "" andalso expected <> baseName path ^ ".wm" then
        TranslateError (path ^ ": structure " ^ self ^ " must be in a file named "
                        ^ CompilerText.slice (expected, 0.0, CompilerText.size expected - 3.0) ^ ".sml")
      else
        Output (baseName path ^ ".wm", Doc.render (src, comments, WmPrint.commentStyle, body),
                conventionWarnings (decs, exps))
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
         | EAndalso (a, b) => EAndalso (go a, go b)
         | EOrelse (a, b) => EOrelse (go a, go b)
         | EIf (c, a, b) => EIf (go c, go a, go b)
         | ECase (x, rs) => ECase (go x, rules rs)
         | EFn rs => EFn (rules rs)
         | ignored77 => e)
    end

  and mapDec = fn (f, d) =>
    case d of
      DVal (p, vs, plain, recs) =>
        let val rules = fn rs => SmlList.map (fn (pat, e) => (pat, mapExp (f, e))) rs in
          DVal (p, vs, rules plain, rules recs)
        end
    | ignored78 => d

  val mapProgram = fn (f, prog) =>
    SmlList.map (fn
        TopDecs sds => TopDecs (SmlList.map (fn
            SDec d => SDec (mapDec (f, d))
          | SStructure (p, binds) => SStructure (p, SmlList.map (fn (n, ds) =>
              (n, SmlList.map (fn d => mapDec (f, d)) ds)) binds)) sds)
      | TopExp (p, e) => TopExp (p, mapExp (f, e))) prog

  (* Workman equality is ambiguous until elaboration. Only a scalar real comparison is
     rewritten; a second, strict elaboration rejects every remaining invalid SML equality. *)
  val realEquality = fn (st, prog) =>
    let
      val Unify.State (ignored79, ignored80, ignored81, ignored82, sites) = st
      val positions = SmlList.map (fn (p, ignored83) => p)
        (SmlList.filter (fn (ignored84, t) =>
           case Unify.prune (st, t) of
             Types.TCon (n, []) => Unify.sameName (n, Types.realName)
           | ignored85 => false) (case sites of SOME xs => xs | NONE => []))
      val rewrite = fn e =>
        case e of
          EApp (EId (p, ([], opr)), a) =>
            if (opr = "=" orelse opr = "<>") andalso SmlList.exists (fn q => Real.== (p, q)) positions
            then EApp (EId (p, (["Real"], if opr = "=" then "==" else "!=")), a)
            else e
        | ignored86 => e
    in
      mapProgram (rewrite, prog)
    end

  (* Check dependencies before a module, regardless of the command-line order. Every
     recovery starts with its dependency closure, so unrelated input files remain independent. *)
  val recover = fn (modules, target) =>
    let
      val nameOfModule = fn (ignored87, ignored88, prog, ignored89) =>
        case structureOf prog of n :: ignored90 => n | [] => ""
      val rec decDeps = fn d =>
        case d of
          DOpen (ignored91, ids) => concatMap (head, ids)
        | ignored92 => decQuals d
      val deps = fn (ignored93, ignored94, prog, ignored95) =>
        distinct (concatMap (fn
            TopDecs sds => concatMap (fn SDec d => decDeps d
              | SStructure (ignored96, bs) => concatMap (fn (ignored97, ds) => concatMap (decDeps, ds), bs), sds)
          | TopExp (ignored98, e) => expQuals e, prog))
      val rec order = fn (item, visiting, done, acc) =>
        let val name = nameOfModule item in
          if SmlList.exists (fn n => n = name) done then Unify.Ok ((done, acc), Unify.initial)
          else (if SmlList.exists (fn n => n = name) visiting then
            Unify.Err ("cyclic module dependency involving " ^ name, 0.0)
          else
            let
              val needed = SmlList.filter (fn m => nameOfModule m <> name andalso
                SmlList.exists (fn n => n = nameOfModule m) (deps item)) modules
              val rec walk = fn
                  ([], done, acc) => Unify.Ok ((name :: done, acc @ [item]), Unify.initial)
                | (m :: rest, done, acc) =>
                    Unify.bind (order (m, name :: visiting, done, acc)) (fn (done, acc) => fn ignored99 =>
                      walk (rest, done, acc))
            in walk (needed, done, acc) end)
        end
      val rec elaborate = fn
          (ignored100, [], st, acc) => Unify.Ok (acc, st)
        | (env, (path, src, prog, comments) :: rest, st, acc) =>
            let val Unify.State (vars, next, sels, recs, ignored101) = st in
              Unify.bind (Elab.program (env, prog, Unify.State (vars, next, sels, recs, SOME [])))
                (fn env => fn st => elaborate (env, rest, st,
                  acc @ [(path, src, realEquality (st, prog), comments)]))
            end
      val rec strict = fn
          (ignored102, [], st) => Unify.Ok ((), st)
        | (env, (ignored103, ignored104, prog, ignored105) :: rest, st) =>
            Unify.bind (Elab.program (env, prog, st)) (fn env => fn st => strict (env, rest, st))
    in
      Unify.bind (order (target, [], [], [])) (fn (ignored106, ordered) => fn ignored107 =>
        Unify.bind Basis.initial (fn basis => fn ignored108 =>
          Unify.bind (elaborate (basis, ordered, Unify.lenient, [])) (fn rewritten => fn ignored109 =>
            Unify.bind (strict (basis, rewritten, Unify.initial)) (fn ignored110 => fn st =>
              case SmlList.find (fn m => nameOfModule m = nameOfModule target) rewritten of
                SOME m => Unify.Ok (m, st)
              | NONE => Unify.Err ("missing translated module", 0.0)))))
    end

  (* A Workman module as SubsetML: its declarations become the structure named by the file. *)
  val fromWm = fn (path, src, decs, exps, comments) =>
    let
      val name = WmParse.structureName path
      (* Imports disappear from the AST. Anchor the structure before them, so comments
         between an import and the first declaration stay inside the structure. *)
      val first =
        case WmLexer.lex src of
          WmLexer.Tokens ((WmLexer.WKey "from", p) :: ignored111, ignored112) => SOME p
        | ignored113 => (case decs of d :: ignored114 => SOME (decPos d) | [] => NONE)
      val structureLine =
        case first of
          SOME p => Doc.atom (p, "structure " ^ name ^ " = struct")
        | NONE => Doc.text ("structure " ^ name ^ " = struct")
      val structureDoc =
        Doc.stack [structureLine,
                   Doc.indent (2.0, Doc.stack (SmlList.map SmlPrint.dec decs)),
                   Doc.text "end"]
      val expDocs = SmlList.map (fn e => Doc.cat (SmlPrint.exp e, Doc.text ";")) exps
      val doc =
        case expDocs of
          [] => structureDoc
        | ignored115 => Doc.stack (Doc.cat (structureDoc, Doc.text ";") :: expDocs)
    in
      Doc.render (src, comments, SmlPrint.commentStyle, doc)
    end

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
