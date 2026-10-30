(* @subsetml
from "./subset_result.sml" import * as SubsetResult;
from "./subset_list.sml" import * as SubsetList;
from "./subset_string.sml" import * as SubsetString;
from "./subset_text.sml" import * as SubsetText;
*)

(* Source-only OS.Path.dir counterpart for slash-separated Unicode paths.
   Lexical only: no normalization, filesystem access, or platform path inference. *)
structure SubsetPath = struct
  val dir = fn value =>
    SubsetResult.map (SubsetText.fields (value, fn scalar => scalar = 47), fn pieces =>
      case SubsetList.reverse pieces of
        [] => ""
      | file :: reversed =>
          let val parent = SubsetList.reverse reversed
          in case parent of
              [""] => "/"
            | rest => SubsetString.concatWith (rest, "/")
          end)
end
