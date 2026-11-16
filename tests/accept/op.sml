(* `op` passes an infix operator as a function value. *)
structure Op = struct
  val sum = fn xs : int list => List.foldl (op +) 0 xs
  val join = fn xs => List.foldr (op ^) "" xs
  val same = fn (a : int, b) => (op =) (a, b)
  val cons = fn x : int => op :: (x, [])
end
