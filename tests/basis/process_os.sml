(* @subsetml
from "../../src/subset_option_value.sml" import * as SubsetOptionValue;
from "../../src/subset_process.sml" import * as SubsetProcess;
from "../../src/subset_os.sml" import * as SubsetOs;
from "../../src/subset_result.sml" import * as SubsetResult;
*)
structure ProcessOs = struct
  val succeeds = fn command =>
    case SubsetProcess.system command of
      SubsetResult.Ok status => SubsetProcess.isSuccess status
    | SubsetResult.Err _ => false
  val checked =
    SubsetProcess.isSuccess SubsetProcess.success andalso
    SubsetOs.Process.isSuccess SubsetOs.Process.success andalso
    not (SubsetProcess.isSuccess SubsetProcess.failure) andalso
    succeeds "printf ran" andalso
    not (succeeds "exit 3") andalso
    (case SubsetProcess.getEnv "SUBSET_PROCESS_PROBE" of
       SubsetOptionValue.SOME "a b" => true
     | _ => false) andalso
    (case SubsetProcess.getEnv "SUBSET_PROCESS_UNSET" of
       SubsetOptionValue.NONE => true
     | _ => false)
  (* A status from system keeps its exit code through exit. *)
  val _ =
    if checked then
      case SubsetProcess.system "exit 3" of
        SubsetResult.Ok status => SubsetProcess.exit status
      | SubsetResult.Err _ => SubsetProcess.exit SubsetProcess.failure
    else SubsetProcess.exit SubsetProcess.failure
end
