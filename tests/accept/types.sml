(* Static semantics the checker must get exactly right (Definition §4). *)

(* Let-polymorphism, and the value restriction (§4.8). *)
val id = fn x => x
val pair = (id 1.0, id "one", id [true])
val empties = ([] : real list, [] : string list)
val compose = fn f => fn g => fn x => f (g x)
val twice = fn f => compose f f
val four = twice (fn n => n + 1.0) 2.0

(* Overloading must be resolved by the context: SML's default, int, is omitted (spec 9.3). *)
val addReal = fn (x : real, y) => x + y
val half = addReal (1.0, 2.5) / 2.0
val less = "a" < "b" andalso #"a" < #"b" andalso 1.0 < 2.0
val negate = ~ 3.0 + abs (~ 4.0)

(* Equality types: datatypes admit equality unless a constructor holds a function. *)
datatype 'a tree = Leaf | Node of 'a tree * 'a * 'a tree
val sameTree = Node (Leaf, "a", Leaf) = Node (Leaf, "a", Leaf)
val member = fn (x, xs) => List.exists (fn y => y = x) xs
val found = member ("b", ["a", "b"])
datatype shape = Circle of real | Square of real
val shapes = [Circle 1.0, Square 2.0]

(* Mutually recursive datatypes and functions. *)
datatype expr = Lit of real | Add of expr * expr | Block of decl list
and decl = Let of string * expr
val rec eval = fn
    Lit n => n
  | Add (a, b) => eval a + eval b
  | Block ds => List.foldl (fn (d, acc) => acc + evalDecl d) 0.0 ds
and evalDecl = fn Let (_, e) => eval e

(* Records under spec §6, and # selection resolved by its context (§4.11). *)
type point = {x : real, y : real}
val origin : point = {x = 0.0, y = 0.0}
val getX = fn (p : point) => #x p
val moved = fn ({x, y} : point) => {x = x + 1.0, y = y} : point

(* Explicit type variables. *)
val 'a self = fn (x : 'a) => x
val swap = fn (x : 'a, y : 'b) => (y, x)

(* Type abbreviations and datatypes local to a let, not escaping. *)
val local1 =
  let
    datatype t = A | B
    type u = t list
    val xs : u = [A, B, A]
  in
    Num.List.length xs
  end

(* Options, orders, and the Basis. *)
val parsed = Num.fromString "42"
val sorted = case Real.compare (1.0, 2.0) of LESS => "less" | EQUAL => "equal" | GREATER => "greater"
val text = String.concatWith ", " (List.map Num.toString [1.0, 2.0, 3.0])
val realEquality = Real.== (0.1 + 0.2, 0.3)
