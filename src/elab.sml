(* Elaboration: the static semantics of the Core and of SubsetML's top-level structures
   (Definition §4, §5), plus the SubsetML restrictions that need types (spec §6, §7, §9).

   Errors stop elaboration: each function returns Unify.res. Declarations elaborate the right
   sides of `val` one level deeper than their context, so that the type variables left above
   the context's level at the end can be generalized (Unify). *)
structure Elab = struct

  open Syntax
  open Unify
  open Env

  (* The context: environment, level, and the explicit type variables in scope. *)
  type context = env * real * string list

  val envOf = fn (env, _, _) => env
  val scopedOf = fn (_, _, scoped) => scoped

  (* --------------------------------------------------------------------------------------- *)
  (* Helpers *)

  val concatMap = fn (f, xs) => SmlList.concat (SmlList.map f xs)

  val member = fn (x, xs) => SmlList.exists (fn y => y = x) xs

  val memberReal = fn (x, xs) => SmlList.exists (fn y => Real.== (y, x)) xs

  val longName = fn (qs, x) => String.concatWith "." (qs @ [x])

  (* Folds a res-returning step over a list. *)
  val rec foldRes = fn (f, acc, xs, st) =>
    case xs of
      [] => Ok (acc, st)
    | x :: rest => bind (f (acc, x, st)) (fn acc' => fn st' => foldRes (f, acc', rest, st'))

  val mapRes = fn (f, xs, st) =>
    bind (foldRes (fn (acc, x, st) => bind (f (x, st)) (fn y => fn st => Ok (acc @ [y], st)), [], xs, st))
      (fn ys => fn st => Ok (ys, st))

  (* The first source position inside a phrase, if any. *)
  val rec patPos = fn p =>
    case p of
      PScon (q, _) => SOME q
    | PId (q, _) => SOME q
    | PRecord (q, _) => SOME q
    | PApp (q, _, _) => SOME q
    | PTuple ps => SmlList.foldl (fn (x, acc) => case acc of SOME _ => acc | NONE => patPos x) NONE ps
    | PList ps => SmlList.foldl (fn (x, acc) => case acc of SOME _ => acc | NONE => patPos x) NONE ps
    | PTyped (q, _) => patPos q
    | PWild => NONE

  val rec expPos = fn e =>
    let val first = fn es => SmlList.foldl (fn (x, acc) => case acc of SOME _ => acc | NONE => expPos x) NONE es in
      case e of
        EScon (q, _) => SOME q
      | EId (q, _) => SOME q
      | ERecord (q, _) => SOME q
      | ESelect (q, _) => SOME q
      | ETuple es => first es
      | EList es => first es
      | ESeq es => first es
      | ELet (_, es) => first es
      | EApp (f, a) => first [f, a]
      | ETyped (x, _) => expPos x
      | EAndalso (a, b) => first [a, b]
      | EOrelse (a, b) => first [a, b]
      | EIf (c, a, b) => first [c, a, b]
      | ECase (x, _) => expPos x
      | EFn rules => (case rules of (p, x) :: _ => (case patPos p of SOME q => SOME q | NONE => expPos x) | [] => NONE)
    end

  val at = fn (fallback, found) =>
    case found of
      SOME q => q
    | NONE => fallback

  (* Unifies, or reports `what` with both types. *)
  val unifyAt = fn (st, pos, what, expected, found) =>
    case unify (st, expected, found) of
      Unified st' => Ok ((), st')
    | Mismatch reason =>
        (case showAll (st, [expected, found]) of
           [e, f] =>
             Err (what ^ ": expected " ^ e ^ ", found " ^ f ^ (if reason = "" then "" else " (" ^ reason ^ ")"), pos)
         | _ => Err (what, pos))

  (* --------------------------------------------------------------------------------------- *)
  (* Type expressions. `tyvar` resolves explicit type variables. *)

  val rec elabTy = fn (env, tyvar, pos, t, st) =>
    case t of
      TyVar v =>
        (case tyvar v of
           SOME t' => Ok (t', st)
         | NONE => Err ("unbound type variable " ^ v, pos))
    | TyCon (args, id) =>
        (case Env.tycon (env, id) of
           NONE => Err ("unbound type constructor " ^ longName id, pos)
         | SOME (TyStr (arity, body, _)) =>
             if Real.!= (arity, Num.List.length args) then
               Err ("type constructor " ^ longName id ^ " takes " ^ Num.toString arity ^ " argument(s), given "
                    ^ Num.toString (Num.List.length args), pos)
             else
               bind (mapRes (fn (a, st) => elabTy (env, tyvar, pos, a, st), args, st)) (fn args' => fn st =>
                 Ok (substGen (args', body), st)))
    | TyTuple ts =>
        bind (mapRes (fn (a, st) => elabTy (env, tyvar, pos, a, st), ts, st)) (fn ts' => fn st =>
          Ok (tupleTy ts', st))
    | TyArrow (a, b) =>
        bind (elabTy (env, tyvar, pos, a, st)) (fn a' => fn st =>
          bind (elabTy (env, tyvar, pos, b, st)) (fn b' => fn st => Ok (TArrow (a', b'), st)))
    | TyRecord fields =>
        bind (mapRes (fn ((l, a), st) => bind (elabTy (env, tyvar, pos, a, st)) (fn a' => fn st => Ok ((l, a'), st)),
                      fields, st)) (fn fields' => fn st =>
          Ok (TRecord (sortFields fields'), st))

  (* An explicit type variable in scope stands for itself. *)
  val scopedTy = fn ((env, _, scoped), pos, t, st) =>
    elabTy (env, fn v => if member (v, scoped) then SOME (TRigid v) else NONE, pos, t, st)

  (* --------------------------------------------------------------------------------------- *)
  (* Explicit type variables occurring unguarded in a value declaration (Definition §4.6):
     those in its annotations, not counting nested value declarations. *)

  val rec tyVarsOf = fn t =>
    case t of
      TyVar v => [v]
    | TyCon (args, _) => concatMap (tyVarsOf, args)
    | TyTuple ts => concatMap (tyVarsOf, ts)
    | TyArrow (a, b) => tyVarsOf a @ tyVarsOf b
    | TyRecord fields => concatMap (fn (_, a) => tyVarsOf a, fields)

  val rec patTyVars = fn p =>
    case p of
      PRecord (_, fields) => concatMap (fn (_, q) => patTyVars q, fields)
    | PTuple ps => concatMap (patTyVars, ps)
    | PList ps => concatMap (patTyVars, ps)
    | PApp (_, _, q) => patTyVars q
    | PTyped (q, t) => patTyVars q @ tyVarsOf t
    | _ => []

  val rec expTyVars = fn e =>
    case e of
      ERecord (_, fields) => concatMap (fn (_, x) => expTyVars x, fields)
    | ETuple es => concatMap (expTyVars, es)
    | EList es => concatMap (expTyVars, es)
    | ESeq es => concatMap (expTyVars, es)
    | ELet (_, es) => concatMap (expTyVars, es)
    | EApp (f, a) => expTyVars f @ expTyVars a
    | ETyped (x, t) => expTyVars x @ tyVarsOf t
    | EAndalso (a, b) => expTyVars a @ expTyVars b
    | EOrelse (a, b) => expTyVars a @ expTyVars b
    | EIf (c, a, b) => expTyVars c @ expTyVars a @ expTyVars b
    | ECase (x, rules) => expTyVars x @ concatMap (fn (p, y) => patTyVars p @ expTyVars y, rules)
    | EFn rules => concatMap (fn (p, y) => patTyVars p @ expTyVars y, rules)
    | _ => []

  val distinct = fn xs => SmlList.foldl (fn (x, acc) => if member (x, acc) then acc else acc @ [x]) [] xs

  (* --------------------------------------------------------------------------------------- *)
  (* SubsetML restrictions *)

  (* Spec B1: the full Basis binds these as constructors; SubsetML leaves them out, so binding
     them as variables would give a program SML reads differently. *)
  val omittedConstructors =
    ["ref", "Match", "Bind", "Chr", "Div", "Domain", "Empty", "Fail", "Option", "Overflow", "Size",
     "Span", "Subscript", "Io"]

  (* The Definition (§2.9) forbids binding these. *)
  val unbindable = ["true", "false", "nil", "::", "ref"]

  (* Spec R3: a record's labels must be those of a record type declaration in scope. *)
  val checkRecordLabels = fn (env, pos, labels, st) =>
    let val sorted = SmlList.map (fn (l, _) => l) (sortFields (SmlList.map (fn l => (l, ())) labels)) in
      if SmlList.exists (fn set => set = sorted) (recordLabelSets env) then Ok ((), st)
      else
        Err ("no record type with the labels {" ^ String.concatWith ", " sorted
             ^ "} is in scope; SubsetML records must have a declared type (spec R3)", pos)
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Patterns: their type and the variables they bind. *)

  val constTy = fn
      SInt _ => intTy
    | SReal _ => realTy
    | SString _ => stringTy
    | SChar _ => charTy

  (* SubsetML omits int (spec §9.3), so integer constants are rejected. *)
  val checkConst = fn (pos, c, st) =>
    case c of
      SInt text =>
        Err ("integer constants are not part of SubsetML, which omits int for now; write " ^ text ^ ".0", pos)
    | _ => Ok (constTy c, st)

  val mergeVars = fn (pos, a, b, st) =>
    case SmlList.find (fn (x, _) => SmlList.exists (fn (y, _) => x = y) a) b of
      SOME (x, _) => Err ("variable " ^ x ^ " is bound twice in a pattern", pos)
    | NONE => Ok (a @ b, st)

  val rec pat = fn (ctx, p, st) =>
    let val (env, level, _) = ctx in
      case p of
        PWild => let val (t, st') = fresh (st, KPlain, level) in Ok ((t, []), st') end
      | PScon (q, c) => bind (checkConst (q, c, st)) (fn t => fn st => Ok ((t, []), st))
      | PId (q, id) =>
          (case (Env.value (env, id), id) of
             (SOME (scheme, SCon), _) =>
               let val (t, st') = instantiate (st, level, scheme) in
                 case prune (st', t) of
                   TArrow _ => Err ("constructor " ^ longName id ^ " needs an argument", q)
                 | _ => Ok ((t, []), st')
               end
           | (_, ([], x)) =>
               if member (x, omittedConstructors) then
                 Err ("`" ^ x ^ "` is a constructor in the SML Basis, which SubsetML omits; it cannot be "
                      ^ "bound as a variable (spec B1)", q)
               else let val (t, st') = fresh (st, KPlain, level) in Ok ((t, [(x, t)]), st') end
           | _ => Err ("unbound constructor " ^ longName id, q))
      | PRecord (q, fields) =>
          bind (checkRecordLabels (env, q, SmlList.map (fn (l, _) => l) fields, st)) (fn _ => fn st =>
            bind (foldRes (fn ((fs, vars), (l, f), st) =>
                             bind (pat (ctx, f, st)) (fn (t, vs) => fn st =>
                               bind (mergeVars (q, vars, vs, st)) (fn vars' => fn st => Ok ((fs @ [(l, t)], vars'), st))),
                           ([], []), fields, st)) (fn (fs, vars) => fn st =>
              Ok ((TRecord (sortFields fs), vars), st)))
      | PTuple ps =>
          bind (pats (ctx, at (0.0, patPos p), ps, st)) (fn (ts, vars) => fn st =>
            Ok ((if SmlList.null ts then unitTy else tupleTy ts, vars), st))
      | PList ps =>
          let val (elem, st0) = fresh (st, KPlain, level) in
            bind (pats (ctx, at (0.0, patPos p), ps, st0)) (fn (ts, vars) => fn st =>
              bind (foldRes (fn (_, (t, x), st) => unifyAt (st, at (0.0, patPos x), "list pattern element", elem, t),
                             (), SmlListPair.zip (ts, ps), st)) (fn _ => fn st =>
                Ok ((listTy elem, vars), st)))
          end
      | PApp (q, id, arg) =>
          (case Env.value (env, id) of
             SOME (scheme, SCon) =>
               let val (t, st') = instantiate (st, level, scheme) in
                 case prune (st', t) of
                   TArrow (dom, cod) =>
                     bind (pat (ctx, arg, st')) (fn (ta, vars) => fn st =>
                       bind (unifyAt (st, at (q, patPos arg), "argument of constructor " ^ longName id, dom, ta))
                         (fn _ => fn st => Ok ((cod, vars), st)))
                 | _ => Err ("constructor " ^ longName id ^ " takes no argument", q)
               end
           | _ => Err ("`" ^ longName id ^ "` is not a constructor", q))
      | PTyped (inner, t) =>
          bind (pat (ctx, inner, st)) (fn (ti, vars) => fn st =>
            bind (scopedTy (ctx, at (0.0, patPos inner), t, st)) (fn t' => fn st =>
              bind (unifyAt (st, at (0.0, patPos inner), "type annotation", t', ti)) (fn _ => fn st =>
                Ok ((t', vars), st))))
    end

  and pats = fn (ctx, pos, ps, st) =>
    foldRes (fn ((ts, vars), p, st) =>
               bind (pat (ctx, p, st)) (fn (t, vs) => fn st =>
                 bind (mergeVars (at (pos, patPos p), vars, vs, st)) (fn vars' => fn st =>
                   Ok ((ts @ [t], vars'), st))),
             ([], []), ps, st)

  (* --------------------------------------------------------------------------------------- *)
  (* Non-expansive expressions (Definition §4.7), which may be generalized. *)

  val rec nonExpansive = fn (env, e) =>
    case e of
      EScon _ => true
    | EId _ => true
    | EFn _ => true
    | ESelect _ => true
    | ERecord (_, fields) => SmlList.all (fn (_, x) => nonExpansive (env, x)) fields
    | ETuple es => SmlList.all (fn x => nonExpansive (env, x)) es
    | EList es => SmlList.all (fn x => nonExpansive (env, x)) es
    | ETyped (x, _) => nonExpansive (env, x)
    | EApp (EId (_, id), arg) =>
        (case Env.value (env, id) of
           SOME (_, SCon) => nonExpansive (env, arg)
         | _ => false)
    | _ => false

  (* --------------------------------------------------------------------------------------- *)
  (* Expressions *)

  val rec exp = fn (ctx, e, st) =>
    let val (env, level, _) = ctx in
      case e of
        EScon (q, c) => checkConst (q, c, st)
      | EId (q, id) =>
          (case Env.value (env, id) of
             SOME (scheme, _) => let val (t, st') = instantiate (st, level, scheme) in Ok (t, st') end
           | NONE => Err ("unbound identifier " ^ longName id, q))
      | ERecord (q, fields) =>
          bind (checkRecordLabels (env, q, SmlList.map (fn (l, _) => l) fields, st)) (fn _ => fn st =>
            bind (mapRes (fn ((l, x), st) => bind (exp (ctx, x, st)) (fn t => fn st => Ok ((l, t), st)), fields, st))
              (fn fs => fn st => Ok (TRecord (sortFields fs), st)))
      | ESelect (q, l) =>
          let
            val (r, st1) = fresh (st, KPlain, level)
            val (f, st2) = fresh (st1, KPlain, level)
            val State (vars, next, sels, recs, eqs) = st2
          in
            Ok (TArrow (r, f), State (vars, next, (q, level, r, l, f) :: sels, recs, eqs))
          end
      | ETuple [] => Ok (unitTy, st)
      | ETuple es => bind (mapRes (fn (x, st) => exp (ctx, x, st), es, st)) (fn ts => fn st => Ok (tupleTy ts, st))
      | EList es =>
          let val (elem, st0) = fresh (st, KPlain, level) in
            bind (foldRes (fn (_, x, st) =>
                             bind (exp (ctx, x, st)) (fn t => fn st =>
                               unifyAt (st, at (0.0, expPos x), "list element", elem, t)), (), es, st0))
              (fn _ => fn st => Ok (listTy elem, st))
          end
      | ESeq es =>
          bind (foldRes (fn (_, x, st) => exp (ctx, x, st), unitTy, es, st)) (fn t => fn st => Ok (t, st))
      | ELet (ds, es) =>
          let val State (_, start, _, _, _) = st in
            bind (decs (ctx, ds, st)) (fn delta => fn st =>
              bind (foldRes (fn (_, x, st) => exp ((plus (env, delta), level, scopedOf ctx), x, st), unitTy, es, st))
                (fn t => fn st =>
                  if SmlList.exists (fn s => s >= start) (tynames (resolve (st, t))) then
                    Err ("the type of this `let` mentions a type declared inside it", at (0.0, expPos e))
                  else Ok (t, st)))
          end
      | EApp (EId (q, ([], opr)), a) =>
          (case (opr = "=" orelse opr = "<>", st) of
             (true, State (_, _, _, _, SOME _)) =>
               bind (exp (ctx, a, st)) (fn ta => fn st =>
                 let val (operand, st1) = fresh (st, KPlain, level) in
                   bind (unifyAt (st1, q, "operands of " ^ opr, tupleTy [operand, operand], ta)) (fn _ => fn st =>
                     let val State (vars, next, sels, recs, sites) = st in
                       Ok (boolTy, State (vars, next, sels, recs,
                                          SOME ((q, operand) :: (case sites of SOME l => l | NONE => []))))
                     end)
                 end)
           | _ => application (ctx, EId (q, ([], opr)), a, st))
      | EApp (f, a) => application (ctx, f, a, st)
      | ETyped (x, t) =>
          bind (exp (ctx, x, st)) (fn tx => fn st =>
            bind (scopedTy (ctx, at (0.0, expPos x), t, st)) (fn t' => fn st =>
              bind (unifyAt (st, at (0.0, expPos x), "type annotation", t', tx)) (fn _ => fn st => Ok (t', st))))
      | EAndalso (a, b) => boolOp (ctx, "andalso", a, b, st)
      | EOrelse (a, b) => boolOp (ctx, "orelse", a, b, st)
      | EIf (c, a, b) =>
          bind (exp (ctx, c, st)) (fn tc => fn st =>
            bind (unifyAt (st, at (0.0, expPos c), "condition of `if`", boolTy, tc)) (fn _ => fn st =>
              bind (exp (ctx, a, st)) (fn ta => fn st =>
                bind (exp (ctx, b, st)) (fn tb => fn st =>
                  bind (unifyAt (st, at (0.0, expPos b), "branches of `if` differ", ta, tb)) (fn _ => fn st =>
                    Ok (ta, st))))))
      | ECase (x, rules) =>
          bind (exp (ctx, x, st)) (fn tx => fn st =>
            bind (matchRules (ctx, rules, st)) (fn (tp, tr) => fn st =>
              bind (unifyAt (st, at (0.0, expPos x), "`case` patterns do not fit the value", tp, tx)) (fn _ => fn st =>
                Ok (tr, st))))
      | EFn rules => bind (matchRules (ctx, rules, st)) (fn (tp, tr) => fn st => Ok (TArrow (tp, tr), st))
    end

  and application = fn (ctx, f, a, st) =>
    let val (_, level, _) = ctx in
      bind (exp (ctx, f, st)) (fn tf => fn st =>
        bind (exp (ctx, a, st)) (fn ta => fn st =>
          let
            val what =
              case f of
                EId (_, id) => "argument of " ^ longName id
              | _ => "function argument"
            val pos = at (0.0, case expPos a of SOME q => SOME q | NONE => expPos f)
          in
            case prune (st, tf) of
              TArrow (dom, cod) => bind (unifyAt (st, pos, what, dom, ta)) (fn _ => fn st => Ok (cod, st))
            | _ =>
                let val (r, st') = fresh (st, KPlain, level) in
                  bind (unifyAt (st', at (pos, expPos f), "applied expression", TArrow (ta, r), tf))
                    (fn _ => fn st => Ok (r, st))
                end
          end))
    end

  and boolOp = fn (ctx, name, a, b, st) =>
    bind (exp (ctx, a, st)) (fn ta => fn st =>
      bind (unifyAt (st, at (0.0, expPos a), "operand of " ^ name, boolTy, ta)) (fn _ => fn st =>
        bind (exp (ctx, b, st)) (fn tb => fn st =>
          bind (unifyAt (st, at (0.0, expPos b), "operand of " ^ name, boolTy, tb)) (fn _ => fn st =>
            Ok (boolTy, st)))))

  (* A match: the type of its patterns and of its results. *)
  and matchRules = fn (ctx, rules, st) =>
    let
      val (env, level, scoped) = ctx
      val (tp, st1) = fresh (st, KPlain, level)
      val (tr, st2) = fresh (st1, KPlain, level)
    in
      bind (foldRes (fn (_, (p, x), st) =>
                       bind (pat (ctx, p, st)) (fn (t, vars) => fn st =>
                         bind (unifyAt (st, at (0.0, patPos p), "patterns of a match differ", tp, t)) (fn _ => fn st =>
                           bind (exp ((plus (env, withValues (SmlList.map (fn (v, vt) => (v, (([], vt), SValue))) vars)),
                                       level, scoped), x, st)) (fn tx => fn st =>
                             unifyAt (st, at (0.0, expPos x), "results of a match differ", tr, tx)))),
                     (), rules, st2))
        (fn _ => fn st => Ok ((tp, tr), st))
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Declarations: each returns the environment it declares. *)

  and decs = fn (ctx, ds, st) =>
    let val (env, level, scoped) = ctx in
      foldRes (fn (delta, d, st) =>
                 bind (dec ((plus (env, delta), level, scoped), d, st)) (fn more => fn st => Ok (plus (delta, more), st)),
               empty, ds, st)
    end

  and dec = fn (ctx, d, st) =>
    case d of
      DVal (pos, tyvars, plain, recs) => valDec (ctx, pos, tyvars, plain, recs, st)
    | DType (pos, binds) => typeDec (ctx, pos, binds, st)
    | DDatatype (pos, binds) => datatypeDec (ctx, pos, binds, st)
    | DOpen (pos, paths) =>
        foldRes (fn (delta, path, st) =>
                   case structureAt (envOf ctx, path) of
                     SOME (_, true) =>
                       Err ("SubsetML can only open structures the program declares, not Basis structure "
                            ^ String.concatWith "." path ^ " (spec F2)", pos)
                   | SOME (found, false) => Ok (plus (delta, found), st)
                   | NONE => Err ("unbound structure " ^ String.concatWith "." path, pos),
                 empty, paths, st)

  (* `val`: Definition §4.10 rules 15-16 and the closure of §4.8. *)
  and valDec = fn ((env, level, scoped), pos, tyvars, plain, recs, st) =>
    let
      val bindings = plain @ recs
      val implicit =
        SmlList.filter (fn v => not (member (v, scoped)))
          (distinct (concatMap (fn (p, e) => patTyVars p @ expTyVars e, bindings)))
      val explicit = distinct (tyvars @ implicit)
      val inner = (env, level + 1.0, scoped @ explicit)
      (* A binding's pattern, its type and variables, checked against its expression's type. *)
      val plainBinding = fn ((p, e), st) =>
        bind (exp (inner, e, st)) (fn te => fn st =>
          bind (pat (inner, p, st)) (fn (tp, vars) => fn st =>
            bind (unifyAt (st, at (pos, patPos p), "value binding", tp, te)) (fn _ => fn st =>
              Ok ((vars, nonExpansive (env, e)), st))))
      (* SubsetML only allows a variable (SML would also let `val rec` rebind a constructor). *)
      val recPattern = fn ((p, _), st) =>
        let val single = fn (_, vars) => fn st =>
          case vars of
            [_] => Ok (vars, st)
          | _ => Err ("a `val rec` binding must bind a variable, not a constructor", at (pos, patPos p))
        in
          case p of
            PId (_, ([], _)) => bind (pat (inner, p, st)) single
          | PTyped (PId (_, ([], _)), _) => bind (pat (inner, p, st)) single
          | _ => Err ("a `val rec` binding must bind a single variable", at (pos, patPos p))
        end
    in
      if SmlList.exists (fn v => member (v, scoped)) tyvars then
        Err ("a type variable is already scoped by an enclosing `val`", pos)
      else
        bind (mapRes (plainBinding, plain, st)) (fn plainResults => fn st =>
          bind (mapRes (recPattern, recs, st)) (fn recVars => fn st =>
            let
              val recEnv = withValues (SmlList.map (fn (v, t) => (v, (([], t), SValue))) (SmlList.concat recVars))
              val recInner = (plus (env, recEnv), level + 1.0, scoped @ explicit)
            in
              bind (foldRes (fn (_, ((_, e), vars), st) =>
                               case vars of
                                 [(_, t)] =>
                                   bind (exp (recInner, e, st)) (fn te => fn st =>
                                     unifyAt (st, at (pos, expPos e), "recursive binding", t, te))
                               | _ => Ok ((), st),
                             (), SmlListPair.zip (recs, recVars), st)) (fn _ => fn st =>
                let
                  val results = plainResults @ SmlList.map (fn vars => (vars, true)) recVars
                in
                  closeValBindings (level, explicit, pos, results, st)
                end)
            end))
    end

  (* Closes a `val`'s bindings: each variable's scheme, given whether its expression may be
     generalized. *)
  and closeValBindings = fn (level, explicit, pos, results, st) =>
    let val names = concatMap (fn (vars, _) => SmlList.map (fn (x, _) => x) vars, results) in
      case (SmlList.find (fn x => Num.List.length (SmlList.filter (fn y => y = x) names) > 1.0) names,
            SmlList.find (fn x => member (x, unbindable)) names) of
        (SOME x, _) => Err ("`" ^ x ^ "` is bound twice in this declaration", pos)
      | (_, SOME x) => Err ("`" ^ x ^ "` cannot be rebound", pos)
      | (NONE, NONE) =>
          bind (closeDeclaration (level, st)) (fn _ => fn st =>
            bind (foldRes (fn (acc, (vars, generalizable), st) =>
                             foldRes (fn (acc, (x, t), st) =>
                                        bind (closeBinding (level, explicit, generalizable, pos, x, t, st))
                                          (fn entry => fn st => Ok (acc @ [entry], st)),
                                      acc, vars, st),
                           [], results, st))
              (fn entries => fn st => Ok (withValues (SmlList.map (fn (x, s) => (x, (s, SValue))) entries), st)))
    end

  (* Settles what the declaration's context must settle (spec §10): pending `# lab`
     selections, and overloaded type variables, which default to int (Appendix E). *)
  and closeDeclaration = fn (level, st) =>
    bind (settleSelections (level, st)) (fn _ => fn st => Ok ((), st))

  and settleSelections = fn (level, st) =>
    let
      val State (vars, next, sels, recs, eqs) = st
      (* One pass: resolves each selection whose record type is known. *)
      val step = fn ((pending, progress), sel, st) =>
        let val (q, l, r, lab, f) = sel in
          case prune (st, r) of
            TRecord fields =>
              (case SmlList.find (fn (l', _) => l' = lab) fields of
                 SOME (_, ft) => bind (unifyAt (st, q, "field " ^ lab, ft, f)) (fn _ => fn st => Ok ((pending, true), st))
               | NONE => Err ("the record has no field " ^ lab ^ ": " ^ show (st, r), q))
          | TVar _ => Ok ((pending @ [sel], progress), st)
          | _ => Err ("`#" ^ lab ^ "` is applied to a non-record: " ^ show (st, r), q)
        end
      val rec loop = fn st =>
        let val State (vs, nx, sels, rs, eq) = st in
          bind (foldRes (step, ([], false), sels, State (vs, nx, [], rs, eq))) (fn (pending, progress) => fn st =>
            let val State (vs', nx', _, rs', eq') = st in
              if progress then loop (State (vs', nx', pending, rs', eq')) else Ok (pending, State (vs', nx', pending, rs', eq'))
            end)
        end
    in
      bind (loop (State (vars, next, sels, recs, eqs))) (fn pending => fn st =>
        case SmlList.find (fn (_, _, r, _, _) =>
                          case prune (st, r) of
                            TVar v => (case lookup (st, v) of Free (_, l) => l > level | Bound _ => false)
                          | _ => false) pending of
          SOME (q, _, _, lab, _) => Err ("cannot determine the record type for `#" ^ lab ^ "`; add a type annotation", q)
        | NONE => Ok ((), st))
    end

  (* The scheme of one bound variable. *)
  and closeBinding = fn (level, explicit, generalizable, pos, x, t, st) =>
    let
      (* An overloaded variable its context has not resolved would default to int in SML
         (Appendix E), which SubsetML omits (spec §9.3). *)
      val unresolved =
        SmlList.exists (fn v => case lookup (st, v) of Free (KClass _, l) => l > level | _ => false)
          (freeVars (st, t))
      val rigid = SmlList.filter (fn v => member (v, explicit)) (rigidNames (resolve (st, t)))
    in
      case (unresolved, generalizable, rigid) of
        (true, _, _) =>
          Err ("the type of an overloaded operation in `" ^ x ^ "` is not determined: SML would make it int, "
               ^ "which SubsetML omits; add a type annotation such as (x : real)", pos)
      | (false, true, _) => Ok ((x, generalize (st, level, explicit, t)), st)
      | (false, false, v :: _) =>
          Err ("type variable " ^ v ^ " cannot be generalized: the value is expansive (Definition, section 4.8)", pos)
      | (false, false, []) => Ok ((x, ([], resolve (st, t))), adjust (st, level, t))
    end

  and rigidNames = fn t =>
    case t of
      TRigid v => [v]
    | TCon (_, ts) => concatMap (rigidNames, ts)
    | TArrow (a, b) => rigidNames a @ rigidNames b
    | TRecord fields => concatMap (fn (_, a) => rigidNames a, fields)
    | _ => []

  (* `type`: Definition §4.10 rule 17, plus spec R2 for record types. *)
  and typeDec = fn ((env, _, _), pos, binds, st) =>
    let
      val names = SmlList.map (fn (_, name, _) => name) binds
      val dup = SmlList.find (fn n => Num.List.length (SmlList.filter (fn m => m = n) names) > 1.0) names
    in
      case dup of
        SOME n => Err ("type " ^ n ^ " is bound twice", pos)
      | NONE =>
          bind (foldRes (fn (acc, (params, name, t), st) =>
                           bind (paramScope (pos, params, st)) (fn tyvar => fn st =>
                             bind (elabTy (env, tyvar, pos, t, st)) (fn body => fn st =>
                               bind (case t of
                                       TyRecord _ => recordDeclared (pos, body, st)
                                     | _ => Ok ((), st)) (fn _ => fn st =>
                                 Ok (acc @ [(name, TyStr (Num.List.length params, body, []))], st)))),
                         [], binds, st))
            (fn tys => fn st => Ok (withTypes tys, st))
    end

  (* Maps a declaration's type parameters to TGen. *)
  and paramScope = fn (pos, params, st) =>
    case SmlList.find (fn v => Num.List.length (SmlList.filter (fn w => w = v) params) > 1.0) params of
      SOME v => Err ("type parameter " ^ v ^ " appears twice", pos)
    | NONE =>
        let
          val rec index = fn
              (_, [], _) => NONE
            | (v, w :: rest, i) => if v = w then SOME (TGen i) else index (v, rest, i + 1.0)
        in
          Ok (fn v => index (v, params, 0.0), st)
        end

  and recordDeclared = fn (pos, body, st) =>
    case body of
      TRecord fields =>
        let
          val labels = SmlList.map (fn (l, _) => l) fields
          val State (vars, next, sels, recs, eqs) = st
        in
          if member (labels, recs) then
            Err ("another record type already has the labels {" ^ String.concatWith ", " labels ^ "} (spec R2)", pos)
          else Ok ((), State (vars, next, sels, labels :: recs, eqs))
        end
    | _ => Ok ((), st)

  (* `datatype`: Definition §4.10 rule 19 and §4.9 for the equality attribute. *)
  and datatypeDec = fn ((env, _, _), pos, binds, st) =>
    let
      val names = SmlList.map (fn (_, name, _) => name) binds
      val cons = concatMap (fn (_, _, cs) => SmlList.map (fn (_, c, _) => c) cs, binds)
      val dupIn = fn xs => SmlList.find (fn n => Num.List.length (SmlList.filter (fn m => m = n) xs) > 1.0) xs
      (* Fresh type names, first assuming every one admits equality. *)
      val (stamps, st1) =
        SmlList.foldl (fn (_, (acc, st)) => let val (s, st') = freshStamp st in (acc @ [s], st') end) ([], st) binds
      val nameFor = fn (eqs, (params, name, _), s) => (s, name, Num.List.length params, memberReal (s, eqs))
      val tyFor = fn tn => TCon (tn, Num.List.tabulate (arityOf tn, TGen))
      (* The constructors' argument types, with the group's names given the equality flags. *)
      val elabCons = fn (eqs, st) =>
        let
          val group = SmlListPair.map (fn (b, s) => nameFor (eqs, b, s)) (binds, stamps)
          val groupEnv = plus (env, withTypes (SmlList.map (fn tn => (nameOf tn, TyStr (arityOf tn, tyFor tn, []))) group))
        in
          bind (mapRes (fn (((params, _, cs), tn), st) =>
                          bind (paramScope (pos, params, st)) (fn tyvar => fn st =>
                            bind (mapRes (fn ((cp, c, arg), st) =>
                                            case arg of
                                              NONE => Ok ((c, NONE), st)
                                            | SOME t => bind (elabTy (groupEnv, tyvar, cp, t, st))
                                                          (fn t' => fn st => Ok ((c, SOME t'), st)),
                                          cs, st)) (fn cs' => fn st => Ok ((tn, cs'), st))),
                        SmlListPair.zip (binds, group), st)) (fn result => fn st => Ok (result, st))
        end
      (* Whether a type admits equality, assuming `eqs` for the group (Definition §4.9). *)
      val rec admits = fn (eqs, t) =>
        case t of
          TCon ((s, _, _, eq), args) =>
            (if memberReal (s, stamps) then memberReal (s, eqs) else eq) andalso SmlList.all (fn a => admits (eqs, a)) args
        | TArrow _ => false
        | TRecord fields => SmlList.all (fn (_, a) => admits (eqs, a)) fields
        | TGen _ => true
        | _ => false
      val rec fixpoint = fn (eqs, st) =>
        bind (elabCons (eqs, st)) (fn group => fn st =>
          let
            val eqs' =
              SmlList.filter (fn s =>
                             SmlList.all (fn ((s', _, _, _), cs) =>
                                         Real.!= (s', s) orelse SmlList.all (fn (_, arg) => case arg of NONE => true
                                                                                          | SOME t => admits (eqs, t)) cs)
                               group) eqs
          in
            if Real.== (Num.List.length eqs', Num.List.length eqs) then Ok (group, st) else fixpoint (eqs', st)
          end)
    in
      case (dupIn names, dupIn cons, SmlList.find (fn c => member (c, unbindable) orelse c = "it") cons) of
        (SOME n, _, _) => Err ("type " ^ n ^ " is bound twice", pos)
      | (_, SOME c, _) => Err ("constructor " ^ c ^ " is bound twice", pos)
      | (_, _, SOME c) => Err ("`" ^ c ^ "` cannot be bound by a datatype", pos)
      | _ =>
          bind (fixpoint (stamps, st1)) (fn group => fn st =>
            let
              val conEntries =
                concatMap (fn (tn, cs) =>
                             SmlList.map (fn (c, arg) =>
                                         let val kinds = Num.List.tabulate (arityOf tn, fn _ => KPlain) in
                                           case arg of
                                             NONE => (c, ((kinds, tyFor tn), SCon))
                                           | SOME t => (c, ((kinds, TArrow (t, tyFor tn)), SCon))
                                         end) cs, group)
              val tyEntries =
                SmlList.map (fn (tn, cs) =>
                            (nameOf tn, TyStr (arityOf tn, tyFor tn,
                                           SmlList.map (fn (c, _) => (c, let val (scheme, _) = valOf (assoc (c, conEntries)) in scheme end)) cs)))
                  group
            in
              Ok (Env ([], tyEntries, conEntries), st)
            end)
    end

  (* --------------------------------------------------------------------------------------- *)
  (* Top-level phrases (Definition §8) *)

  val strdec = fn (env, sd, st) =>
    case sd of
      SDec d => dec ((env, 0.0, []), d, st)
    | SStructure (_, binds) =>
        foldRes (fn (delta, (name, ds), st) =>
                   bind (decs ((env, 0.0, []), ds, st)) (fn body => fn st =>
                     Ok (plus (delta, withStructure (name, body, false)), st)),
                 empty, binds, st)

  val topdec = fn (env, td, st) =>
    case td of
      TopDecs sds =>
        foldRes (fn (delta, sd, st) =>
                   bind (strdec (plus (env, delta), sd, st)) (fn more => fn st => Ok (plus (delta, more), st)),
                 empty, sds, st)
    | TopExp (pos, e) => dec ((env, 0.0, []), DVal (pos, [], [(PId (pos, ([], "it")), e)], []), st)

  (* Elaborates a file's phrases in order, extending the environment. *)
  val program = fn (env, phrases, st) =>
    foldRes (fn (env, td, st) => bind (topdec (env, td, st)) (fn delta => fn st => Ok (plus (env, delta), st)),
             env, phrases, st)

end
