(* Real primitives with no portable SubsetML implementation. Checker/roundtrip declarations;
   the native SML adapter is lib/subset_real_host.sml and the Workman target adapter is
   lib/subset_real_host.wm.

   `rem` is the remainder of division truncated toward zero, with the dividend's sign
   (C's fmod, JS's `%`). `toString` is the shortest text that reads back as the same real,
   written as JavaScript's Number#toString writes it, which is how Workman shows a Real64:
   `1`, `0.30000000000000004`, `1e+21`, `-1.5e-7`, `NaN`, `-Infinity`.

   `fromInt` is the real of an int, which is exact. `toInt` is the int of a real its caller has
   checked to be integral and within the int range (SubsetInt32.fromReal64). *)
structure SubsetRealHost = struct
  val rem = fn (dividend : real, divisor : real) => dividend
  val toString = fn (value : real) => ""
  val fromInt = fn (value : int) => 0.0
  val toInt = fn (value : real) => 0
end
