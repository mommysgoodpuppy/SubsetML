(* Process arguments are host byte strings; exit accepts success/failure only. *)
structure SubsetProcess = struct
  val arguments = fn () =>
    SubsetResult.andThen (
      SubsetResult.mapError (SubsetHost.arguments (), fn message => SubsetIo.HostError message),
      fn values => SubsetList.traverse (values, fn value =>
        SubsetResult.map (SubsetIo.bytes value, fn bytes => value)))
  (* Exit never returns, including in the portable type system. *)
  val exit = fn success =>
    let
      val () = SubsetHost.exit success
      val rec unreachable = fn () => unreachable ()
    in unreachable () end
end
