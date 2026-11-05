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
  datatype status = Status of int
  val success = Status 0
  val failure = Status 1
  val isSuccess = fn Status code => code = 0
  val system = fn (command : string) =>
    (SubsetResult.Err "host adapter not staged" : (status, string) SubsetResult.result)
  val getEnv = fn (name : string) => (SubsetOptionValue.NONE : string SubsetOptionValue.option)
  val exit = fn (status : status) => ()
  val terminate = fn (status : status) => ()
end
