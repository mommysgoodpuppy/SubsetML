(* error: real constants may not occur in patterns *)
val f = fn 1.0 => 0 | _ => 1
