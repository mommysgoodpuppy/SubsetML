(* error: unbound identifier hidden *)
structure LocalScope = struct
  local val hidden = 1 in val shown = hidden + 1 end
  val leaked = hidden
end
