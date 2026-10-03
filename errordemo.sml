(* @subsetml
from "./src/subset_result.sml" import * as SubsetResult;
*)

(* Procedure-style error propagation in ordinary SubsetML.
   Build: mlton -output /tmp/errordemo errordemo.mlb
   Input reading/decoding are toy operations;
   the demo needs no file I/O or native parsing primitive. *)
structure Errordemo = struct
  datatype error =
      InputFailure of string
    | ParseFailure of string
    | ValidationFailure of string

  val via = SubsetResult.via
  val viaError = SubsetResult.viaError

  val readInput = fn input =>
    if input = "missing" then SubsetResult.Err "input unavailable"
    else SubsetResult.Ok input

  val decode = fn
      "12" => SubsetResult.Ok 12.0
    | "zero" => SubsetResult.Ok 0.0
    | other => SubsetResult.Err "expected 12 or zero"

  val requirePositive = fn number =>
    if number > 0.0 then SubsetResult.Ok "compiled"
    else SubsetResult.Err (ValidationFailure "expected a positive number")

  val compileInput = fn input =>
    let
      val read = viaError InputFailure readInput
      val parse = viaError ParseFailure decode
      val compile = via requirePositive

      val loaded = read (SubsetResult.Ok input)
      val parsed = parse loaded
    in
      compile parsed
    end

  (* Different input/output types compose; errors retain their original stage. *)
  val checked =
    compileInput "12" = SubsetResult.Ok "compiled"
    andalso compileInput "missing" = SubsetResult.Err (InputFailure "input unavailable")
    andalso compileInput "bad" = SubsetResult.Err (ParseFailure "expected 12 or zero")
    andalso compileInput "zero" = SubsetResult.Err (ValidationFailure "expected a positive number")

  (* A later stage has an observable effect, so this checks actual skipping too. *)
  val skipped =
    via (fn value => let val () = print "FAILED: skipped stage ran\n"
                    in SubsetResult.Ok value end)
      (SubsetResult.Err (InputFailure "earlier failure"))
    = SubsetResult.Err (InputFailure "earlier failure")

  val _ =
    if checked andalso skipped then print "error procedure demo: ok\n"
    else print "error procedure demo: FAILED\n"
end
