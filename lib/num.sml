(* Num: the real-typed counterparts of the Basis functions whose types mention int (spec §9.3).

   Legacy consumers with real-valued indices use these instead of String.size, List.nth,
   Char.ord and the rest. SubsetML now also supports int. This file is full SML, not SubsetML.
   The translator has provisional mappings into Workman's current library. These interfaces
   are bootstrap compatibility scaffolding, not the final custom SubsetML Basis API.

   Arguments that must be integers are checked: a real that is not an integer, or does not fit
   in int, raises Domain. Results are exact (int fits in a 64-bit real). *)
structure BasisString = String
structure BasisList = List
structure BasisChar = Char
structure BasisCharVector = CharVector

structure Num = struct

  fun toInt x =
    if Real.isFinite x andalso Real.== (Real.realFloor x, x)
       andalso x >= Real.fromInt (valOf Int.minInt) andalso x <= Real.fromInt (valOf Int.maxInt)
    then Real.toInt IEEEReal.TO_NEAREST x
    else raise Domain

  val fromInt = Real.fromInt

  (* Floored division and modulo of integers, as SML's int div and mod (and Workman's
     Number.div and Number.mod). Division by zero raises Div. *)
  fun op div (a, b) = fromInt (Int.div (toInt a, toInt b))
  fun op mod (a, b) = fromInt (Int.mod (toInt a, toInt b))

  (* Integers print without a fraction, in SML's notation: 3, ~3, 2.5. *)
  fun toString x =
    if Real.isFinite x andalso Real.== (Real.realFloor x, x) andalso Real.abs x < 1.0E15
    then LargeInt.toString (Real.toLargeInt IEEEReal.TO_NEAREST x)
    else Real.toString x

  fun fromString s = Option.map fromInt (Int.fromString s)

  structure String = struct
    fun size s = fromInt (BasisString.size s)
    fun sub (s, i) = BasisString.sub (s, toInt i)
    fun substring (s, i, n) = BasisString.substring (s, toInt i, toInt n)
    fun extract (s, i, n) = BasisString.extract (s, toInt i, Option.map toInt n)
  end

  structure List = struct
    fun length xs = fromInt (BasisList.length xs)
    fun nth (xs, i) = BasisList.nth (xs, toInt i)
    fun take (xs, n) = BasisList.take (xs, toInt n)
    fun drop (xs, n) = BasisList.drop (xs, toInt n)
    fun tabulate (n, f) = BasisList.tabulate (toInt n, fn i => f (fromInt i))
  end

  structure Char = struct
    fun ord c = fromInt (BasisChar.ord c)
    fun chr n = BasisChar.chr (toInt n)
  end

  structure CharVector = struct
    fun tabulate (n, f) = BasisCharVector.tabulate (toInt n, fn i => f (fromInt i))
  end

end
