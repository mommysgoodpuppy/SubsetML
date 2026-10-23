(* @subsetml
from "../../src/subset_process.sml" import * as SubsetProcess;
from "../../src/subset_io.sml" import * as SubsetIo;
from "../../src/subset_result.sml" import * as SubsetResult;
*)
structure ProcessPanic = struct
  (* The terminal result stays polymorphic, including as a first-class function. *)
  val number : string -> real = SubsetProcess.panic
  val boolean : string -> bool = SubsetProcess.panic
  val function : string -> (real -> real) = SubsetProcess.panic
  val message = fn () =>
    case SubsetIo.writeStdout [#"o", #"n", #"c", #"e"] of
      SubsetResult.Ok () => "unreachable\000\255"
    | SubsetResult.Err _ => "stdout unavailable"
  val result : real = number (message ())
  val _ = SubsetIo.writeStdout [#"B", #"A", #"D"]
end
