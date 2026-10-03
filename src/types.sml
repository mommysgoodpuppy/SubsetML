(* @subsetml
from "./subset_list.sml" import * as SubsetList;
from "./compiler_text.sml" import * as CompilerText;
from "./subset_char.sml" import * as SubsetChar;
from "./sml_list.sml" import * as SmlList;
from "./subset_result.sml" import * as SubsetResult;
*)

(* Semantic types (Definition §4.2), as the type checker represents them. *)
structure Types = struct

  (* A type name (Definition §4.1): its stamp, its printed name, its arity, and whether it
     admits equality, given type arguments that do. *)
  type tyname = real * string * real * bool

  datatype ty =
      TVar of real                       (* unification variable; see Unify *)
    | TGen of real                       (* the i-th bound variable of a type scheme *)
    | TRigid of string                  (* an explicit type variable 'a in scope *)
    | TCon of tyname * ty list
    | TArrow of ty * ty
    | TRecord of (string * ty) list     (* labels in canonical order; tuples use 1, 2, ... *)

  (* What a type variable may stand for: any type, a type admitting equality, or one of the
     type names of an overloading class (Appendix E). *)
  datatype kind =
      KPlain
    | KEq
    | KClass of tyname list

  (* A type scheme: the kinds of its bound variables, and its body, which refers to them with
     TGen. *)
  type scheme = kind list * ty

  val stampOf = fn (s, _, _, _) => s
  val nameOf = fn (_, n, _, _) => n
  val arityOf = fn (_, _, a, _) => a

  (* --------------------------------------------------------------------------------------- *)
  (* The type names of the initial basis. Program type names get stamps from `firstStamp`. *)

  val boolName = (1.0, "bool", 0.0, true)
  val intName = (2.0, "int", 0.0, true)
  val realName = (3.0, "real", 0.0, false)
  val stringName = (4.0, "string", 0.0, true)
  val charName = (5.0, "char", 0.0, true)
  val listName = (6.0, "list", 1.0, true)
  val optionName = (7.0, "option", 1.0, true)
  val orderName = (8.0, "order", 0.0, true)
  val firstStamp = 100.0

  val boolTy = TCon (boolName, [])
  val intTy = TCon (intName, [])
  val realTy = TCon (realName, [])
  val stringTy = TCon (stringName, [])
  val charTy = TCon (charName, [])
  val unitTy = TRecord []
  val listTy = fn t => TCon (listName, [t])

  (* --------------------------------------------------------------------------------------- *)
  (* Records. Numeric labels come first, in numeric order, then the others alphabetically. *)

  val isNumeric = fn l => SubsetList.all (CompilerText.characters l, SubsetChar.isDigit)

  val labelLess = fn (a, b) =>
    case (isNumeric a, isNumeric b) of
      (true, true) => CompilerText.size a < CompilerText.size b orelse (Real.== (CompilerText.size a, CompilerText.size b) andalso CompilerText.less (a, b))
    | (true, false) => true
    | (false, true) => false
    | (false, false) => CompilerText.less (a, b)

  (* Insertion sort: records are small. *)
  val sortFields = fn fields =>
    let
      val rec insert = fn
          (f, []) => [f]
        | ((l, t), (l', t') :: rest) =>
            if labelLess (l, l') then (l, t) :: (l', t') :: rest else (l', t') :: insert ((l, t), rest)
    in
      SmlList.foldl insert [] fields
    end

  (* Tuple labels are a decimal counter, stored least significant digit first.
     Carry is source character matching; no numeric formatter or division is needed. *)
  val rec nextTupleLabel = fn
      [] => [#"1"]
    | #"9" :: rest => #"0" :: nextTupleLabel rest
    | #"0" :: rest => #"1" :: rest
    | #"1" :: rest => #"2" :: rest
    | #"2" :: rest => #"3" :: rest
    | #"3" :: rest => #"4" :: rest
    | #"4" :: rest => #"5" :: rest
    | #"5" :: rest => #"6" :: rest
    | #"6" :: rest => #"7" :: rest
    | #"7" :: rest => #"8" :: rest
    | #"8" :: rest => #"9" :: rest

  val tupleLabel = fn digits => CompilerText.stringOf (SubsetList.reverse digits)

  val tupleTy = fn ts =>
    let
      val rec number = fn
          (_, []) => []
        | (digits, t :: rest) => (tupleLabel digits, t) :: number (nextTupleLabel digits, rest)
    in
      TRecord (number ([#"1"], ts))
    end

  (* The components of a tuple type, if the labels are exactly 1, ..., n with n >= 2. *)
  val tupleComponents = fn fields =>
    let
      val rec check = fn
          (_, []) => true
        | (digits, (l, _) :: rest) => l = tupleLabel digits andalso check (nextTupleLabel digits, rest)
    in
      if SubsetList.length fields >= 2.0 andalso check ([#"1"], fields) then SOME (SmlList.map (fn (_, t) => t) fields) else NONE
    end

  (* Replaces TGen i by the i-th argument. *)
  val rec substGen = fn (args, t) =>
    case t of
      TGen i => let val SubsetResult.Ok t = SubsetList.at (args, i) in t end
    | TCon (n, ts) => TCon (n, SmlList.map (fn a => substGen (args, a)) ts)
    | TArrow (a, b) => TArrow (substGen (args, a), substGen (args, b))
    | TRecord fields => TRecord (SmlList.map (fn (l, a) => (l, substGen (args, a))) fields)
    | _ => t

  (* The stamps of the type names a type mentions. *)
  val rec tynames = fn t =>
    case t of
      TCon (n, ts) => stampOf n :: SmlList.concat (SmlList.map tynames ts)
    | TArrow (a, b) => tynames a @ tynames b
    | TRecord fields => SmlList.concat (SmlList.map (fn (_, a) => tynames a) fields)
    | _ => []

end
