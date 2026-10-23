structure IntegerBasics = struct
  val lo : int = ~2147483648
  val hi = 2147483647
  val hexadecimal = ~0x80000000
  val add = fn (a : int, b) => a + b
  val subtract = fn (a : int, b) => a - b
  val multiply = fn (a : int, b) => a * b
  val divide = fn (a : int, b) => a div b
  val modulo = fn (a : int, b) => a mod b
  val negate = fn (a : int) => ~a
  val absolute = fn (a : int) => abs a
  val defaulted = fn (a, b) => a + b
  val ordering = fn (a : int, b) => a < b
  val equal = fn (a : int, b) => a = b
  val realAdd = fn (a : real, b) => a + b
  val text = Int.toString hi
  val parsed = Int.fromString "2147483647"
  val precision = Int.precision
  val maximum = Int.maxInt
  val minimum = Int.minInt
  val classify = fn 0 => "zero" | ~2147483648 => "minimum" | _ => "other"
  datatype count = Count of int
  val count = Count hi
  val shadow = let val abs = fn (n : int) => n + 1 in abs 5 end
  val shadowType = let type int = string val value : int = "text" in value end
  val rec sum = fn (n : int, acc : int) =>
    if n = 0 then acc else sum (n - 1, acc + n)
end
