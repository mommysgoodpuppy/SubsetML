(* @subsetml
from "./subset_process.sml" import * as SubsetProcess;
from "./subset_path.sml" import * as SubsetPath;
*)

(* The Basis OS structure. OS.FileSys and OS.IO aren't provided yet. *)
structure SubsetOs = struct
  structure Process = SubsetProcess
  structure Path = SubsetPath
end
