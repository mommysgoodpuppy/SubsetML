(* error: mentions type hidden, which this `local` declares privately *)
structure LocalRecordLeak = struct
  local
    type hidden = { secret : int }
  in
    val leak : hidden = { secret = 1 }
  end
end
