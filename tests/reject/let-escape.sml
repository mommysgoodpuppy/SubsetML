(* error: mentions a type declared inside it *)
val v = let datatype t = A in A end
