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
    | PScon _ => []
    | PId (_, (qs, _)) => head qs
    | PRecord (_, fields) => concatMap (fn (_, p) => patQuals p, fields)
    | PTuple ps => concatMap (patQuals, ps)
    | PList ps => concatMap (patQuals, ps)
    | PApp (_, (qs, _), p) => head qs @ patQuals p
    | PTyped (p, t) => patQuals p @ tyQuals t

  val rec expQuals = fn
      EScon _ => []
    | EId (_, (qs, _)) => head qs
    | ERecord (_, fields) => concatMap (fn (_, e) => expQuals e, fields)
    | ESelect _ => []
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
      | DOpen _ => d
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Coding conventions (docs/conventions.md). Breaking one gives a warning, because the
     Workman output would be invalid or mean something else. *)

  (* Workman keywords that SML treats as ordinary identifiers. *)
  val wmKeywords = ["match", "record", "from", "import", "void"]

  val isUpper = fn s => s <> "" andalso SubsetChar.isUpper (Num.String.sub (s, 0.0))

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
      | EScon _ => []
    end

  and ruleNames = fn (pos, rules) => concatMap (fn (p, e) => patNames (pos, p) @ expNames (pos, e), rules)

  and decNames = fn
      DVal (pos, _, plain, recs) => ruleNames (pos, plain @ recs)
    | DType (pos, binds) => SmlList.map (fn (_, tycon, _) => (pos, tycon)) binds
    | DDatatype (pos, binds) =>
        concatMap (fn (_, tycon, cons) => (pos, tycon) :: SmlList.map (fn (cp, c, _) => (cp, c)) cons, binds)
    | DOpen _ => []

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
        case SmlList.rev (String.fields (fn c => c = #"/") path) of
          last :: _ => last
        | [] => path
    in
      if String.isSuffix ".sml" file then Num.String.substring (file, 0.0, Num.String.size file - 4.0) else file
    end

  (* The file's structure name, or "" when it has none. *)
  val structureOf = fn prog =>
    concatMap (fn
        TopDecs sds => concatMap (fn SStructure (_, binds) => SmlList.map (fn (name, _) => name) binds | SDec _ => [], sds)
      | TopExp _ => [], prog)

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
    (concatMap (fn TopDecs sds => concatMap (fn SDec d => [d] | SStructure _ => [], sds)
                 | TopExp _ => [], phrases),
     concatMap (fn TopExp (_, e) => [e] | TopDecs _ => [], phrases))

  (* Translates one parsed file. `structures` names every structure of the program. *)
  val toWm = fn (structures, path, src, prog, comments) =>
    let
      val (self, phrases) = module prog
      val (decs, exps) = parts phrases
      val used = distinct (concatMap (decQuals, decs) @ concatMap (expQuals, exps))
      val start =
        case prog of
          TopDecs (SStructure (p, _) :: _) :: _ => p
        | _ => 0.0
      val imports =
        SmlList.map (fn q => Doc.atom (start, "from \"./" ^ WmPrint.fileName q ^ "\" import * as " ^ q ^ ";"))
          (SmlList.filter (fn q => q <> self andalso SmlList.exists (fn s => s = q) structures) used)
      val doc = Doc.stack (SmlList.map (fn td => WmPrint.topdec (structures, td)) phrases)
      val body =
        case imports of
          [] => doc
        | _ => Doc.stack [Doc.stack imports, Doc.text "", doc]
      val expected = WmPrint.fileName self
    in
      if self <> "" andalso expected <> baseName path ^ ".wm" then
        TranslateError (path ^ ": structure " ^ self ^ " must be in a file named "
                        ^ Num.String.substring (expected, 0.0, Num.String.size expected - 3.0) ^ ".sml")
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

  (* Workman equality is ambiguous until elaboration. Only a scalar real comparison is
     rewritten; a second, strict elaboration rejects every remaining invalid SML equality. *)
  val realEquality = fn (st, prog) =>
    let
      val Unify.State (_, _, _, _, sites) = st
      val positions = SmlList.map (fn (p, _) => p)
        (SmlList.filter (fn (_, t) =>
           case Unify.prune (st, t) of
             Types.TCon (n, []) => Unify.sameName (n, Types.realName)
           | _ => false) (case sites of SOME xs => xs | NONE => []))
      val rewrite = fn e =>
        case e of
          EApp (EId (p, ([], opr)), a) =>
            if (opr = "=" orelse opr = "<>") andalso SmlList.exists (fn q => Real.== (p, q)) positions
            then EApp (EId (p, (["Real"], if opr = "=" then "==" else "!=")), a)
            else e
        | _ => e
    in
      mapProgram (rewrite, prog)
    end

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
            Unify.Err ("cyclic module dependency involving " ^ name, 0.0)
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
              Unify.bind (Elab.program (env, prog, Unify.State (vars, next, sels, recs, SOME [])))
                (fn env => fn st => elaborate (env, rest, st,
                  acc @ [(path, src, realEquality (st, prog), comments)]))
            end
      val rec strict = fn
          (_, [], st) => Unify.Ok ((), st)
        | (env, (_, _, prog, _) :: rest, st) =>
            Unify.bind (Elab.program (env, prog, st)) (fn env => fn st => strict (env, rest, st))
    in
      Unify.bind (order (target, [], [], [])) (fn (_, ordered) => fn _ =>
        Unify.bind Basis.initial (fn basis => fn _ =>
          Unify.bind (elaborate (basis, ordered, Unify.lenient, [])) (fn rewritten => fn _ =>
            Unify.bind (strict (basis, rewritten, Unify.initial)) (fn _ => fn st =>
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
          WmLexer.Tokens ((WmLexer.WKey "from", p) :: _, _) => SOME p
        | _ => (case decs of d :: _ => SOME (decPos d) | [] => NONE)
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
        | _ => Doc.stack (Doc.cat (structureDoc, Doc.text ";") :: expDocs)
    in
      Doc.render (src, comments, SmlPrint.commentStyle, doc)
    end

  (* Reprints a parsed file as SubsetML. *)
  val toSml = fn (src, prog, comments) =>
    let
      (* A declaration phrase needs its `;` when an expression phrase follows (Definition §8). *)
      val rec phrases = fn
          [] => []
        | TopDecs sds :: (TopExp e :: rest) =>
            Doc.cat (SmlPrint.topdec (TopDecs sds), Doc.text ";") :: phrases (TopExp e :: rest)
        | td :: rest => SmlPrint.topdec td :: phrases rest
    in
      Doc.render (src, comments, SmlPrint.commentStyle, Doc.stack (phrases prog))
    end

end
