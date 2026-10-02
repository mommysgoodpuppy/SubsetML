(* error: cannot be generalized *)
val 'a f = (fn () => fn (x : 'a) => x) ()
