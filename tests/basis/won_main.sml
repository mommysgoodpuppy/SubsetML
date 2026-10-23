(* Writes probe results as bytes, so native and Workman runs print identical output. *)
structure WonMain = struct
  val show = fn (mode, input) =>
    let val (ok, text) = WonProbe.run (mode, input) in
      SubsetResult.andThen (SubsetIo.bytes ((if ok then "ok " else "error ") ^ text ^ "\n"),
        SubsetIo.writeStdout)
    end
  val selftest = show ("selftest", "")
  val emit = show ("emit", "")
end
