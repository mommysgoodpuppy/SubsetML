(* Static environments (Definition §4.2): structures, types and values, newest binding first. *)
structure Env = struct

  open Types

  (* Value identifier status: a variable or a value constructor (no exceptions in SubsetML). *)
  datatype status =
      SValue
    | SCon

  (* A type structure: a type function (arity, and a body over TGen 0 .. arity-1) and the
     value constructors when it is a datatype. *)
  datatype tystr = TyStr of real * ty * (string * scheme) list

  (* Structures (each marked if it comes from the Basis), types, and values. *)
  datatype env =
      Env of (string * (env * bool)) list * (string * tystr) list * (string * (scheme * status)) list

  val empty = Env ([], [], [])

  (* `plus (a, b)`: b's bindings shadow a's. *)
  val plus = fn (Env (s1, t1, v1), Env (s2, t2, v2)) => Env (s2 @ s1, t2 @ t1, v2 @ v1)

  val assoc = fn (key, entries) =>
    case SmlList.find (fn (k, _) => k = key) entries of
      SOME (_, v) => SOME v
    | NONE => NONE

  (* The environment of a structure path, with whether it comes from the Basis. *)
  val rec structureAt = fn (env, path) =>
    case path of
      [] => SOME (env, false)
    | name :: rest =>
        let val Env (strs, _, _) = env in
          case assoc (name, strs) of
            SOME (inner, basis) =>
              (case structureAt (inner, rest) of
                 SOME (found, innerBasis) => SOME (found, basis orelse innerBasis)
               | NONE => NONE)
          | NONE => NONE
        end

  val value = fn (env, (quals, x)) =>
    case structureAt (env, quals) of
      SOME (Env (_, _, vals), _) => assoc (x, vals)
    | NONE => NONE

  val tycon = fn (env, (quals, x)) =>
    case structureAt (env, quals) of
      SOME (Env (_, tys, _), _) => assoc (x, tys)
    | NONE => NONE

  val withValues = fn vals => Env ([], [], vals)
  val withTypes = fn tys => Env ([], tys, [])
  val withStructure = fn (name, env, basis) => Env ([(name, (env, basis))], [], [])

  (* The label sets of the record type declarations in scope (spec R3). *)
  val recordLabelSets = fn Env (_, tys, _) =>
    SmlList.concat (SmlList.map (fn (_, TyStr (_, TRecord fields, _)) => [SmlList.map (fn (l, _) => l) fields] | _ => []) tys)

end
