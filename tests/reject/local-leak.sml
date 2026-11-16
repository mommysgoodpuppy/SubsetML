(* error: mentions type step, which this `local` declares privately *)
structure Leak = struct
  local
    datatype step = Step of int
  in
    val first = Step 1
  end
end
