(* @subsetml
from "./subset_real_host.sml" import * as SubsetRealHost;
*)

(* Workman's real operations. Equality is portable; the remainder and text are host
   primitives (SubsetRealHost). *)
structure SubsetReal = struct
  (* IEEE equality, Workman's `==` on reals: NaN equals nothing, and 0.0 equals -0.0. A NaN
     operand makes both comparisons false. *)
  val equal = fn (left : real, right : real) => left <= right andalso right <= left

  (* Workman's `%`: truncated toward zero, with the dividend's sign. *)
  val rem = SubsetRealHost.rem

  (* Text as Workman shows a Real64: `1`, `0.5`, `1e+21`, `NaN`. *)
  val toString = SubsetRealHost.toString
end
