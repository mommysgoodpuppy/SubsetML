(* Checker/round-trip declarations for the six host operations.
   Native builds and staged Workman graphs replace this module with their adapters. *)
structure SubsetHost = struct
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
  val exit = fn (success : bool) => ()
end
