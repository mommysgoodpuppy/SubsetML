(* Shared Standard ML Basis target adapter (Unix byte-I/O profile).
   Exceptions are caught here; authored SubsetML receives ordinary Result values.
   Used by both MLton and MLWorks; load a coherent Basis before this file. *)
structure SubsetHost = struct
  fun protect operation f = SubsetResult.Ok (f ())
    handle error => SubsetResult.Err (operation ^ ": " ^ General.exnMessage error)

  fun path value =
    if List.exists (fn c => c = #"\000") (String.explode value)
    then raise Fail "NUL in path" else value

  fun closeQuietly close stream = close stream handle _ => ()
  fun canonicalPath name = protect "canonicalPath" (fn () => OS.FileSys.fullPath (path name))
  fun readFile name = protect "readFile" (fn () =>
    let
      val input = BinIO.openIn (path name)
      val bytes = BinIO.inputAll input
        handle error => (closeQuietly BinIO.closeIn input; raise error)
      val () = BinIO.closeIn input
    in Byte.bytesToString bytes end)
  fun writeFile (data, name) = protect "writeFile" (fn () =>
    let
      val output = BinIO.openOut (path name)
      val () = BinIO.output (output, Byte.stringToBytes data)
        handle error => (closeQuietly BinIO.closeOut output; raise error)
    in BinIO.closeOut output end)

  (* Unix MLWorks TextIO preserves bytes. Flush before returning so failures
     are reported to the caller, rather than deferred until process exit. *)
  fun writeStream (stream, data) = (TextIO.output (stream, data); TextIO.flushOut stream)
  fun writeStdout data = protect "writeStdout" (fn () => writeStream (TextIO.stdOut, data))
  fun writeStderr data = protect "writeStderr" (fn () => writeStream (TextIO.stdErr, data))
  fun arguments () = protect "arguments" CommandLine.arguments
  (* An exit code, not OS.Process.status: MLton's system returns a raw wait status, which its own
     exit rejects, so the code has to be recovered here to survive the trip from system to exit. *)
  fun exitCode status = case Unix.fromStatus status of
      Unix.W_EXITED => 0
    | Unix.W_EXITSTATUS code => Word8.toInt code
    | Unix.W_SIGNALED _ => 1
    | Unix.W_STOPPED _ => 1
  fun system command = protect "system" (fn () => exitCode (OS.Process.system (path command)))
  fun getEnv name = case OS.Process.getEnv name of
      Option.NONE => SubsetOptionValue.NONE
    | Option.SOME value => SubsetOptionValue.SOME value
  fun exit status : unit =
    if status = 0 then OS.Process.exit OS.Process.success
    else if status = 1 then OS.Process.exit OS.Process.failure
    else Unix.exit (Word8.fromInt status)
  fun terminate status : unit =
    if status = 0 then OS.Process.terminate OS.Process.success
    else if status = 1 then OS.Process.terminate OS.Process.failure
    else Unix.exit (Word8.fromInt status)

  fun makeDir name = protect "makeDir" (fn () => OS.FileSys.mkDir (path name))
  fun removeDir name = protect "removeDir" (fn () => OS.FileSys.rmDir (path name))
  fun removeFile name = protect "removeFile" (fn () => OS.FileSys.remove (path name))
  fun rename (source, destination) = protect "rename" (fn () =>
    OS.FileSys.rename {old = path source, new = path destination})
  fun isDir name = protect "isDir" (fn () => OS.FileSys.isDir (path name))
  fun listDir name = protect "listDir" (fn () =>
    let
      val stream = OS.FileSys.openDir (path name)
      fun collect acc = case OS.FileSys.readDir stream of
          NONE => List.rev acc
        | SOME "." => collect acc
        | SOME ".." => collect acc
        | SOME entry => collect (entry :: acc)
      val entries = collect []
        handle error => (closeQuietly OS.FileSys.closeDir stream; raise error)
      val () = OS.FileSys.closeDir stream
    in entries end)
end
