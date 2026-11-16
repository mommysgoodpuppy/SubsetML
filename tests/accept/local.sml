(* `local`: the hidden declarations, including a datatype, are visible only in the body. *)
structure Local = struct
  local
    datatype step = Step of int
    val unit = Step 1
    val rec advance = fn (Step n, k) => if k = 0 then n else advance (Step (n + 1), k - 1)
  in
    val count = fn k => advance (unit, k)
    val twice = fn k => count k + count k
  end
  val answer = twice 20
  val nested = let local val x = 2 in val y = x * x end in y + answer end
end
