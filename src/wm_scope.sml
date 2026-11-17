(* @subsetml
from "./syntax.sml" import * as Syntax;
from "./subset_option_value.sml" import * as SubsetOptionValue;
from "./subset_list.sml" import * as SubsetList;
from "./subset_bool.sml" import * as SubsetBool;
from "./wm_print.sml" import * as WmPrint;
*)

(* Resolve default library bindings after parsing. Defaults are projections, not opens: only
   the selected names enter scope, and an ordinary binding always wins. Discovery may load a
   conservative dependency set; this pass never rewrites a declaration or a record label. *)
structure WmScope = struct
  open SubsetOptionValue
  open Syntax

  datatype scope = Scope of (string * bool) list * string list
  val empty = Scope ([], [])
  val member = fn (names, name) => SubsetList.exists (names, fn n => n = name)
  val plus = fn (Scope (av, at), Scope (bv, bt)) =>
    Scope (SubsetList.append (bv, av), SubsetList.append (bt, at))
  val value = fn (Scope (values, _), name) => SubsetList.find (values, fn (n, _) => n = name)
  val typeBound = fn (Scope (_, types), name) => member (types, name)

  (* Each table maps a source spelling to its defining module and member. Namespace targets
     are canonical project names, rather than basenames or source aliases. *)
  val resolve = fn (values, types, namespaces, imports, declarations) =>
    let
      val find = fn (table, name) => SubsetList.find (table, fn (n, _) => n = name)
      val namespace = fn name => case find (namespaces, name) of
          SOME (_, target) => SOME target | NONE => NONE
      (* The standalone reader's bootstrap numeric spellings precede this scope pass. Undo
         them only when the source namespace is supplied by the selected library. *)
      val sourceId = fn id => case SubsetList.find (WmPrint.numNames, fn (sml, wm) =>
          sml = id andalso (case wm of (head :: _, _) =>
            (case namespace head of SOME _ => true | NONE => false) | _ => false)) of
          SOME (_, wm) => wm | NONE => id
      val resolveId = fn (env, isType, (qs, name)) =>
        case qs of
          [] => if (if isType then typeBound (env, name) else
                     case value (env, name) of SOME _ => true | NONE => false)
                then (qs, name)
                else (case find (if isType then types else values, name) of
                  SOME (_, target) => target | NONE => (qs, name))
        | head :: tail => (case namespace head of
            SOME target => (target :: tail, name) | NONE => (qs, name))
      val constructor = fn (env, name) => case value (env, name) of
          SOME (_, flag) => flag
        | NONE => member (["true", "false", "nil", "::", "NONE", "SOME"], name) orelse
            SubsetList.exists (values, fn (n, _) => n = name andalso
              member (["Less", "Equal", "Greater", "Ok", "Err"], n))
      val rec ty = fn (env, t) => case t of
          TyVar _ => t
        | TyCon (args, id) => TyCon (SubsetList.map (args, fn t => ty (env, t)), resolveId (env, true, id))
        | TyTuple ts => TyTuple (SubsetList.map (ts, fn t => ty (env, t)))
        | TyArrow (a, b) => TyArrow (ty (env, a), ty (env, b))
        | TyRecord fs => TyRecord (SubsetList.map (fs, fn (l, t) => (l, ty (env, t))))
      val rec pat = fn (env, p) => case p of
          PId (pos, ([], name)) =>
            if constructor (env, name) then (PId (pos, resolveId (env, false, ([], name))), empty)
            else (p, Scope ([(name, false)], []))
        | PId (pos, id) => (PId (pos, resolveId (env, false, id)), empty)
        | PPinned (pos, id) => (PPinned (pos, resolveId (env, false, id)), empty)
        | PComputed (pos, e) => (PComputed (pos, exp (env, e)), empty)
        | PApp (pos, id, inner) =>
            let val (inner, delta) = pat (env, inner)
            in (PApp (pos, resolveId (env, false, id), inner), delta) end
        | PRecord (pos, fs) =>
            let val (ps, delta) = pats (env, SubsetList.map (fs, fn (_, p) => p))
                val rec zip = fn (fs, ps) => case (fs, ps) of
                    ((l, _) :: fs, p :: ps) => (l, p) :: zip (fs, ps) | _ => []
            in (PRecord (pos, zip (fs, ps)), delta) end
        | PTuple ps => let val (ps, delta) = pats (env, ps) in (PTuple ps, delta) end
        | PList ps => let val (ps, delta) = pats (env, ps) in (PList ps, delta) end
        | PTyped (p, t) => let val (p, delta) = pat (env, p) in (PTyped (p, ty (env, t)), delta) end
        | _ => (p, empty)
      and pats = fn (env, ps) => case ps of
          [] => ([], empty)
        | p :: rest => let val (p, delta) = pat (env, p)
                          val (rest, more) = pats (env, rest)
                      in (p :: rest, plus (delta, more)) end
      and exp = fn (env, e) =>
        let val e = case e of EId (p, id) => EId (p, sourceId id) | _ => e
            val go = fn e => exp (env, e)
            val rules = fn rs => SubsetList.map (rs, fn (p, e) =>
              let val (p, delta) = pat (env, p) in (p, exp (plus (env, delta), e)) end)
        in case e of
          EId (pos, ([], name)) => (case value (env, name) of
              SOME _ => e
            | NONE => (case find (values, name) of
                SOME (_, target) => EId (pos, target)
              | NONE => (case namespace name of
                  SOME target => EId (pos, ([target], "carrier")) | NONE => e)))
        | EId (pos, (head :: tail, name)) =>
            (* An uppercase local value can be a record receiver, just like a lowercase one. *)
            (case value (env, head) of
               SOME (_, false) => SubsetList.foldLeft (SubsetList.append (tail, [name]),
                 EId (pos, ([], head)), fn (field, receiver) => EApp (ESelect (pos, field), receiver))
             | _ => EId (pos, resolveId (env, false, (head :: tail, name))))
        | ERecord (pos, fs) => ERecord (pos, SubsetList.map (fs, fn (l, e) => (l, go e)))
        | ETuple es => ETuple (SubsetList.map (es, go))
        | EList es => EList (SubsetList.map (es, go))
        | ESeq es => ESeq (SubsetList.map (es, go))
        | ELet (ds, es) => let val (ds, delta) = decs (env, ds)
                          in ELet (ds, SubsetList.map (es, fn e => exp (plus (env, delta), e))) end
        | EApp (a, b) => EApp (go a, go b)
        | ETyped (e, t) => ETyped (go e, ty (env, t))
        | EAndalso (a, b) => EAndalso (go a, go b)
        | EOrelse (a, b) => EOrelse (go a, go b)
        | EIf (c, a, b) => EIf (go c, go a, go b)
        | ECase (e, rs) => ECase (go e, rules rs)
        | EFn rs => EFn (rules rs)
        | ECopy (pos, a, b, t) => ECopy (pos, go a, go b, ty (env, t))
        | _ => e end
      and dec = fn (env, d) => case d of
          DVal (pos, vs, plain, recs) =>
            let val (pp, pd) = pats (env, SubsetList.map (plain, fn (p, _) => p))
                val (rp, rd) = pats (env, SubsetList.map (recs, fn (p, _) => p))
                val pe = SubsetList.map (plain, fn (_, e) => exp (env, e))
                val re = SubsetList.map (recs, fn (_, e) => exp (plus (env, rd), e))
                val rec zip = fn (ps, es) => case (ps, es) of
                    (p :: ps, e :: es) => (p, e) :: zip (ps, es) | _ => []
            in (DVal (pos, vs, zip (pp, pe), zip (rp, re)), plus (pd, rd)) end
        | DType (pos, bs) =>
            (DType (pos, SubsetList.map (bs, fn (vs, n, t) => (vs, n, ty (env, t)))),
             Scope ([], SubsetList.map (bs, fn (_, n, _) => n)))
        | DDatatype (pos, bs) =>
            let val delta = Scope (SubsetList.concat (SubsetList.map (bs, fn (_, _, cs) =>
                      SubsetList.map (cs, fn (_, n, _) => (n, true)))),
                    SubsetList.map (bs, fn (_, n, _) => n))
                val env = plus (env, delta)
            in (DDatatype (pos, SubsetList.map (bs, fn (vs, n, cs) => (vs, n,
                 SubsetList.map (cs, fn (p, c, t) => (p, c, case t of
                   NONE => NONE | SOME t => SOME (ty (env, t))))))), delta) end
        | DOpen (_, paths) => (d, SubsetList.foldLeft (paths, empty, fn (path, delta) =>
            case path of [name] => (case find (imports, name) of
              SOME (_, scope) => plus (delta, scope) | NONE => delta) | _ => delta))
        | DLocal (pos, hidden, body) =>
            let val (hidden, hd) = decs (env, hidden)
                val (body, bd) = decs (plus (env, hd), body)
            in (DLocal (pos, hidden, body), bd) end
      and decs = fn (env, ds) => case ds of
          [] => ([], empty)
        | d :: rest => let val (d, delta) = dec (env, d)
                           val (rest, more) = decs (plus (env, delta), rest)
                       in (d :: rest, plus (delta, more)) end
    in decs (empty, declarations) end

  (* Module references after lexical resolution, including type-only dependencies. *)
  val moduleReferences = fn program =>
    let
      val flat = fn (xs, f) => SubsetList.concat (SubsetList.map (xs, f))
      val id = fn (qs, _) => case qs of head :: _ => [head] | [] => []
      val rec ty = fn t => case t of
          TyCon (args, name) => SubsetList.append (id name, flat (args, ty))
        | TyTuple ts => flat (ts, ty)
        | TyArrow (a, b) => SubsetList.append (ty a, ty b)
        | TyRecord fs => flat (fs, fn (_, t) => ty t)
        | _ => []
      val rec pat = fn p => case p of
          PId (_, name) => id name | PPinned (_, name) => id name
        | PComputed (_, e) => exp e
        | PApp (_, name, p) => SubsetList.append (id name, pat p)
        | PRecord (_, fs) => flat (fs, fn (_, p) => pat p)
        | PTuple ps => flat (ps, pat) | PList ps => flat (ps, pat)
        | PTyped (p, t) => SubsetList.append (pat p, ty t)
        | _ => []
      and exp = fn e => case e of
          EId (_, name) => id name
        | ERecord (_, fs) => flat (fs, fn (_, e) => exp e)
        | ETuple es => flat (es, exp) | EList es => flat (es, exp) | ESeq es => flat (es, exp)
        | ELet (ds, es) => SubsetList.append (flat (ds, dec), flat (es, exp))
        | EApp (a, b) => SubsetList.append (exp a, exp b)
        | ETyped (e, t) => SubsetList.append (exp e, ty t)
        | EAndalso (a, b) => SubsetList.append (exp a, exp b)
        | EOrelse (a, b) => SubsetList.append (exp a, exp b)
        | EIf (c, a, b) => flat ([c, a, b], exp)
        | ECase (e, rs) => SubsetList.append (exp e, rules rs)
        | EFn rs => rules rs
        | ECopy (_, a, b, t) => SubsetList.concat [exp a, exp b, ty t]
        | _ => []
      and rules = fn rs => flat (rs, fn (p, e) => SubsetList.append (pat p, exp e))
      and dec = fn d => case d of
          DVal (_, _, plain, recs) => rules (SubsetList.append (plain, recs))
        | DType (_, bs) => flat (bs, fn (_, _, t) => ty t)
        | DDatatype (_, bs) => flat (bs, fn (_, _, cs) => flat (cs,
            fn (_, _, t) => case t of SOME t => ty t | NONE => []))
        | DOpen (_, paths) => flat (paths, fn path => case path of head :: _ => [head] | [] => [])
        | DLocal (_, hidden, body) => flat (SubsetList.append (hidden, body), dec)
      val names = flat (program, fn phrase => case phrase of
          TopExp (_, e) => exp e
        | TopDecs ss => flat (ss, fn s => case s of
            SDec d => dec d
          | SStructure (_, bs) => flat (bs, fn (_, aliases, ds) =>
              SubsetList.append (SubsetList.map (aliases, fn (_, _, target) => target), flat (ds, dec)))))
    in SubsetList.foldLeft (names, [], fn (n, found) => if member (found, n) then found else n :: found) end

  (* Closed native projects need no unused library function definitions. In particular, a
     generic WM display function has no SML implementation until its argument's display is
     known. Retain every entry/user function and every library initializer; remove only
     unused library lambda bindings. Reference collection is deliberately conservative about
     local shadowing and opens. No effectful initializer is a candidate for removal. *)
  val pruneLibraries = fn (libraries, modules) =>
    let
      val flat = fn (xs, f) => SubsetList.concat (SubsetList.map (xs, f))
      val rec patternRefs = fn p => case p of
          PComputed (_, e) => expressionRefs e
        | PPinned (_, id) => [id]
        | PId (_, (qs, n)) => if SubsetList.isEmpty qs then [] else [(qs, n)]
        | PApp (_, id, p) => id :: patternRefs p
        | PRecord (_, fs) => flat (fs, fn (_, p) => patternRefs p)
        | PTuple ps => flat (ps, patternRefs)
        | PList ps => flat (ps, patternRefs)
        | PTyped (p, _) => patternRefs p
        | _ => []
      and expressionRefs = fn e => case e of
          EId (_, id) => [id]
        | ERecord (_, fs) => flat (fs, fn (_, e) => expressionRefs e)
        | ETuple es => flat (es, expressionRefs)
        | EList es => flat (es, expressionRefs)
        | ESeq es => flat (es, expressionRefs)
        | ELet (ds, es) => SubsetList.append (flat (ds, declarationRefs), flat (es, expressionRefs))
        | EApp (a, b) => SubsetList.append (expressionRefs a, expressionRefs b)
        | ETyped (e, _) => expressionRefs e
        | EAndalso (a, b) => SubsetList.append (expressionRefs a, expressionRefs b)
        | EOrelse (a, b) => SubsetList.append (expressionRefs a, expressionRefs b)
        | EIf (c, a, b) => flat ([c, a, b], expressionRefs)
        | ECase (e, rs) => SubsetList.append (expressionRefs e, ruleRefs rs)
        | EFn rs => ruleRefs rs
        | ECopy (_, a, b, _) => SubsetList.append (expressionRefs a, expressionRefs b)
        | _ => []
      and ruleRefs = fn rs => flat (rs, fn (p, e) =>
        SubsetList.append (patternRefs p, expressionRefs e))
      and declarationRefs = fn d => case d of
          DVal (_, _, plain, recs) => ruleRefs (SubsetList.append (plain, recs))
        | DLocal (_, hidden, body) => flat (SubsetList.append (hidden, body), declarationRefs)
        | _ => []
      val functionNames = fn d => case d of
          DVal (_, _, plain, recs) =>
            let val bs = SubsetList.append (plain, recs)
            in if SubsetList.all (bs, fn (PId (_, ([], _)), EFn _) => true | _ => false)
               then flat (bs, fn (PId (_, ([], n)), _) => [n] | _ => []) else [] end
        | _ => []
      val rec flatten = fn ds => flat (ds, fn d => case d of
          DLocal (_, hidden, body) => flatten (SubsetList.append (hidden, body)) | _ => [d])
      val contents = flat (modules, fn (owner, _, (_, _, prog, _)) => flat (prog, fn phrase => case phrase of
          TopDecs ss => flat (ss, fn s => case s of
            SStructure (_, bs) => flat (bs, fn (_, aliases, ds) =>
              [(owner, aliases, flatten ds)]) | SDec d => [(owner, [], flatten [d])])
        | TopExp (_, e) => [(owner, [], [DVal (0, [], [(PWild, e)], [])])]))
      val nodes = flat (contents, fn (owner, _, ds) => flat (ds, fn d =>
        SubsetList.map (functionNames d, fn n => ((owner, n), declarationRefs d))))
      val opens = flat (contents, fn (owner, _, ds) => flat (ds, fn d => case d of
        DOpen (_, paths) => flat (paths, fn [target] => [(owner, target)] | _ => []) | _ => []))
      val aliases = flat (contents, fn (owner, aliases, _) =>
        SubsetList.map (aliases, fn (_, alias, target) => (owner, alias, target)))
      val rec qualify = fn (owner, (qs, n)) => case qs of
          [] => [(owner, n)]
        | [target] => [(target, n)]
        | head :: alias :: tail => (case SubsetList.find (aliases,
            fn (moduleName, name, _) => moduleName = head andalso name = alias) of
              SOME (_, _, target) => qualify (owner, (target :: tail, n))
            | NONE => SubsetList.map (nodes, fn (key, _) => key))
      val roots = flat (contents, fn (owner, _, ds) => flat (ds, fn d =>
        if member (libraries, owner) andalso SubsetBool.not (SubsetList.isEmpty (functionNames d)) then []
        else flat (declarationRefs d, fn id => qualify (owner, id))))
      val roots = SubsetList.append (roots, flat (aliases, fn (_, _, target) =>
        flat (nodes, fn (key, _) => let val (owner, _) = key in if owner = target then [key] else [] end)))
      val roots = SubsetList.append (roots, flat (opens, fn (owner, target) =>
        if member (libraries, owner) then [] else
          SubsetList.map (nodes, fn ((_, n), _) => (target, n))))
      val sameKey = fn ((a : string, b : string), (c : string, d : string)) => a = c andalso b = d
      val rec reach = fn (todo : (string * string) list, seen : (string * string) list) => case todo of
          [] => seen
        | key :: rest => if SubsetList.exists (seen, fn k => sameKey (k, key)) then reach (rest, seen) else
            let val (owner, n) = key
                val direct = flat (SubsetList.filter (nodes, fn (k, _) => sameKey (k, key)),
                  fn (_, ids) => flat (ids, fn id => qualify (owner, id)))
                val opened = flat (SubsetList.filter (opens, fn (moduleName, _) => moduleName = owner),
                  fn (_, target) => [(target, n)])
            in reach (SubsetList.concat [direct, opened, rest], key :: seen) end
      val used = reach (roots, [])
      val rec prune = fn (owner, ds) => flat (ds, fn d => case d of
          DLocal (p, hidden, body) =>
            let val hidden = prune (owner, hidden)
                val body = prune (owner, body)
            in if SubsetList.isEmpty hidden then body else [DLocal (p, hidden, body)] end
        | _ => let val names = functionNames d in
            if SubsetList.isEmpty names orelse SubsetList.exists (names,
              fn n => SubsetList.exists (used, fn key => sameKey (key, (owner, n)))) then [d] else [] end)
    in SubsetList.map (modules, fn (owner, deps, (path, src, prog, cs)) =>
      (owner, deps, (path, src, if member (libraries, owner) then
        SubsetList.map (prog, fn phrase => case phrase of
          TopDecs ss => TopDecs (SubsetList.map (ss, fn s => case s of
            SStructure (p, bs) => SStructure (p, SubsetList.map (bs, fn (n, aliases, ds) =>
              (n, aliases, prune (owner, ds)))) | _ => s)) | _ => phrase)
        else prog, cs))) end
end
