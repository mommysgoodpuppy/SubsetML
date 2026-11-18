(* @subsetml
from "./subset_numeric.sml" import * as SubsetNumeric;
from "./subset_real_host.sml" import * as SubsetRealHost;
*)

(* Workman's real operations. Equality is portable; the remainder and text are host
   primitives (SubsetRealHost). *)
structure SubsetReal64 = struct
  (* IEEE equality, Workman's `==` on reals: NaN equals nothing, and 0.0 equals -0.0. A NaN
     operand makes both comparisons false. *)
  val equal = fn (left : real, right : real) => left <= right andalso right <= left

  (* Workman's `%`: truncated toward zero, with the dividend's sign. *)
  val rem = SubsetRealHost.rem

  (* Text as Workman shows a Real64: `1`, `0.5`, `1e+21`, `NaN`. *)
  val toString = SubsetRealHost.toString

  val math : real SubsetNumeric.arithmetic = {
    zero = 0.0, one = 1.0,
    add = fn (a : real, b : real) => a + b,
    mul = fn (a : real, b : real) => a * b
  }
  val carrier = math

end
