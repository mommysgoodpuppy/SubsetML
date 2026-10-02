(* A tour of the kept Core forms. *)
datatype 'a tree = Leaf | Node of 'a tree * 'a * 'a tree

val rec insert = fn
    (x, Leaf) => Node (Leaf, x, Leaf)
  | (x : real, Node (l, y, r)) =>
      case Real.compare (x, y) of
          LESS => Node (insert (x, l), y, r)
        | GREATER => Node (l, y, insert (x, r))
        | EQUAL => Node (l, y, r)

val rec toList = fn
    Leaf => []
  | Node (l, x, r) => toList l @ x :: toList r

val sorted = toList (List.foldl insert Leaf [5.0, 3.0, 8.0, 1.0, 4.0])

val curried = fn a => fn b => fn (c : real) => a + b * c
val seven = curried 1.0 2.0 3.0

val rec fact = fn n => if Real.== (n, 0.0) then 1.0 else n * fact (n - 1.0)

val rec even = fn n => Real.== (n, 0.0) orelse odd (n - 1.0)
and odd = fn n => Real.!= (n, 0.0) andalso even (n - 1.0)

val one = 1.0 and rec loop = fn n => if n <= 0.0 then 1.0 else loop (n - 1.0)

type name = string
type ('a, 'b) pair = 'a * 'b

val greeting : name = "hi\tthere\n\^G\065B\
                      \ gap"
val c = #"x"
val r = ~1.5e~3 + 2.0
val first = case (1.0, "one") of (n, _) => n

val describe =
  fn n =>
    case Real.compare (n, 0.0) of
        LESS => "negative"
      | EQUAL => "zero"
      | GREATER => "positive"

val both = not ("a" = "b") andalso (true orelse false)
val seq = (print ""; 3.0)
val composed = (fn x => x + 1.0) o (fn x => x * 2.0)
val withLet = let val a = 1.0; val b = 2.0 in a; a + b end
val typed = (fn (x : real) => x) (3.0 : real)
val listPat = case ["a", "b"] of [a, b] => a ^ b | x :: _ => x | [] => ""
val _ = 1.0 before ()
val q = Num.div (7.0, 2.0) + Num.mod (7.0, 2.0) + 7.0 / 2.0
val s = "a" ^ "b" = "ab"
val 'a ident = fn (x : 'a) => x
val nested = fn x => fn y => x andalso (if y then x else false)
val size = Num.String.size "four" + Num.List.length [1.0, 2.0]
