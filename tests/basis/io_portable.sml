(* Actual byte I/O: the shell fixture verifies file contents and both output streams. *)
structure IoPortable = struct
  val success = fn result => case result of SubsetResult.Ok value => true | SubsetResult.Err error => false
  val run = fn (input, output, missing) =>
    let
      val read = case SubsetIo.readFile input of
        SubsetResult.Ok bytes => bytes = SubsetChar.byteChars | SubsetResult.Err error => false
      val absent = case SubsetIo.readFile missing of
        SubsetResult.Err (SubsetIo.HostError message) => true | other => false
      val invalid = case SubsetIo.writeFile ([#"x"], "bad\000path") of
        SubsetResult.Err SubsetIo.InvalidPath => true | other => false
      val written = success (SubsetIo.writeFile (SubsetChar.byteChars, output))
      val checked = read andalso absent andalso invalid andalso written
      val out = success (SubsetIo.writeStdout SubsetChar.byteChars)
      val err = success (SubsetIo.writeStderr SubsetChar.byteChars)
    in SubsetProcess.exit (checked andalso out andalso err) end
  val _ = case SubsetProcess.arguments () of
    SubsetResult.Ok [input, output, missing] => run (input, output, missing)
  | other => SubsetProcess.exit false
end
