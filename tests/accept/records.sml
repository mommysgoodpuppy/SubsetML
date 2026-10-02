(* Records under spec §6: declared by `type`, unique label sets, no `...`. *)
type point = { x : real, y : real }
type 'a labelled = { value : 'a, label : string }

val origin : point = { x = 0.0, y = 0.0 }
val norm1 = fn ({ x, y } : point) => abs x + abs y
val shift = fn ({ x = a, y = b } : point) => { x = a + 1.0, y = b + 1.0 } : point
val l : real labelled = { label = "n", value = 3.0 }
val v = #value l
