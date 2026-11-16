(* A structure-level `local` is Workman's `private`: the hidden declarations, a datatype
   included, are visible to the rest of the structure and not to importers. *)
structure PrivateLocal = struct
  val visible = 1
  local
    datatype step = Step of int
    val unit = Step visible
    val rec advance = fn (Step n, k) => if k = 0 then n else advance (Step (n + 1), k - 1)
  in
    val count = fn k => advance (unit, k)
    local
      val base = 10
    in
      val total = count base
    end
  end
end
