(* @subsetml
from "./subset_option_value.sml" import * as SubsetOptionValue;
from "./subset_result.sml" import * as SubsetResult;
*)

(* Checker/round-trip declarations for the CLI and filesystem identity operations.
   Native builds and staged Workman graphs replace this module with their adapters. *)
structure SubsetHost = struct
  val canonicalPath = fn (path : string) =>
    (SubsetResult.Err "host adapter not staged" : (string, string) SubsetResult.result)
  val readFile = fn (path : string) =>
    (SubsetResult.Err "host adapter not staged" : (string, string) SubsetResult.result)
  val writeFile = fn (data : string, path : string) =>
    (SubsetResult.Err "host adapter not staged" : (unit, string) SubsetResult.result)
  val writeStdout = fn (data : string) =>
    (SubsetResult.Err "host adapter not staged" : (unit, string) SubsetResult.result)
  val writeStderr = fn (data : string) =>
    (SubsetResult.Err "host adapter not staged" : (unit, string) SubsetResult.result)
  val arguments = fn () =>
    (SubsetResult.Err "host adapter not staged" : (string list, string) SubsetResult.result)
  val system = fn (command : string) =>
    (SubsetResult.Err "host adapter not staged" : (int, string) SubsetResult.result)
  val getEnv = fn (name : string) => (SubsetOptionValue.NONE : string SubsetOptionValue.option)
  val exit = fn (code : int) => ()
  val terminate = fn (code : int) => ()
end
