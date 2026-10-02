(* Function values, aliases, higher-order calls, and names shadowed by the expansion. *)
val equal = Real.==
val unequal = Real.!=
val both = fn (f, g, x, y) => f (x, y) andalso not (g (x, y))
val same = both (Real.==, Real.!=, 2.0, 2.0)
val realLeft = "outer left"
val realRight = "outer right"
val passed = List.exists (fn f => f (1.0, 1.0)) [Real.==, equal]
val flipped = fn (x : real, y : real) => Real.== (y, x)
val negated = fn (x : real, y : real) => not (Real.== (x, y))
