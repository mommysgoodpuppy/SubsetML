(* @subsetml
from "../../src/subset_result.sml" import * as SubsetResult;
from "../../src/subset_host.sml" import * as SubsetHost;
*)
(* Runs through the generated loader, not the fixed three-module WM harness. *)
structure SmlTargetProbe = struct
  val plus = fn (a, b) => a + b
  val argumentsOK = case SubsetHost.arguments () of
      SubsetResult.Ok ["from", "PS2"] => true
    | _ => false
  val integerOK = plus (2147483647, ~2147483647) = 0
  val _ = if argumentsOK andalso integerOK then
      (case SubsetHost.writeStdout "SML_TARGET_LOADER_OK\n" of
        SubsetResult.Ok () => SubsetHost.exit true
      | SubsetResult.Err _ => SubsetHost.exit false)
    else SubsetHost.exit false
end
