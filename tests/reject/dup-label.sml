(* error: appears twice in a record expression *)
type p = {x : int}  val q = {x = 1, x = 2}
