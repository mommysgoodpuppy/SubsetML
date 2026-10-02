(* Persistent maps from non-negative integers (held in reals: SubsetML omits int for now), as
   a binary trie on the key's bits, lowest bit first. SubsetML has no references, so the type
   checker threads its substitution through one of these. Lookup and insertion take time
   proportional to the number of key bits. *)
structure IntMap = struct

  datatype 'a map =
      Empty
    | Leaf of real * 'a
    | Branch of 'a map * 'a map

  val empty = Empty

  val even = fn n => Real.== (Num.mod (n, 2.0), 0.0)

  (* `rest` is the key shifted right by the current depth. *)
  val rec lookup = fn (m, key, rest) =>
    case m of
      Empty => NONE
    | Leaf (k, v) => if Real.== (k, key) then SOME v else NONE
    | Branch (l, r) => lookup (if even rest then l else r, key, Num.div (rest, 2.0))

  val find = fn (m, key) => lookup (m, key, key)

  (* `scale` is 2 to the power of the current depth, to shift a displaced leaf's key. *)
  val rec insertAt = fn (m, key, rest, scale, v) =>
    case m of
      Empty => Leaf (key, v)
    | Leaf (k, old) =>
        if Real.== (k, key) then Leaf (key, v)
        else
          insertAt (if even (Num.div (k, scale)) then Branch (Leaf (k, old), Empty)
                    else Branch (Empty, Leaf (k, old)),
                    key, rest, scale, v)
    | Branch (l, r) =>
        if even rest then Branch (insertAt (l, key, Num.div (rest, 2.0), scale * 2.0, v), r)
        else Branch (l, insertAt (r, key, Num.div (rest, 2.0), scale * 2.0, v))

  val insert = fn (m, key, v) => insertAt (m, key, key, 1.0, v)

end
