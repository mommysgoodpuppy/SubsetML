(* Full-SML compiler preflight. Load one coherent Basis first.
   Integer-only applications need not run this check. SubsetML's compiler
   currently requires correct real-valued counters and comparisons. *)
local
  val checks = [
    ("int conversion", Real.== (Real.fromInt 65, 65.0)),
    ("addition", Real.== (1.0 + 2.0, 3.0)),
    ("subtraction", Real.== (3.0 - 2.0, 1.0)),
    ("multiplication", Real.== (2.0 * 3.0, 6.0)),
    ("division", Real.== (4.0 / 2.0, 2.0)),
    ("ordering", 1.0 < 2.0 andalso not (2.0 < 1.0))]
  val () = List.app (fn (name, passed) => print
    ("SML real " ^ name ^ ": " ^ (if passed then "OK" else "FAILED") ^ "\n")) checks
in
  val () = if List.all (fn (_, passed) => passed) checks
    then print "SML_TARGET_NUMERIC_OK\n"
    else OS.Process.exit OS.Process.failure
end
