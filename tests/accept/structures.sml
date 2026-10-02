(* One top-level structure (spec §7, M1), with other top-level declarations beside it. *)
val before1 = 1.0

structure Structures = struct
  datatype 'a stack = Empty | Push of 'a * 'a stack
  val empty = Empty
  val push = fn (x, s) => Push (x, s)
  val top = fn Empty => NONE | Push (x, _) => SOME x
  val ok = OS.Process.success
end;

Structures.top (Structures.push (before1, Structures.empty));
val it2 = 1.0 + 2.0
