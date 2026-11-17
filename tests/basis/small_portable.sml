(* Portable contracts exercised as SML, roundtripped SML and generated WM. *)
structure SmallPortable = struct
  val same = fn (result, expected) => case result of
      SubsetResult.Ok value => value = expected | SubsetResult.Err error => false
  val overflow = fn result => case result of
      SubsetResult.Err SubsetInt32.Overflow => true | other => false
  val invalid = fn result => case result of
      SubsetResult.Err SubsetInt32.InvalidInteger => true | other => false
  val integers = same (SubsetInt32.fromString " \t~12tail", ~12)
    andalso same (SubsetInt32.fromString "+12.5", 12)
    andalso same (SubsetInt32.fromString "-2147483648", ~2147483648)
    andalso same (SubsetInt32.parseDecimal "~2147483648", ~2147483648)
    andalso same (SubsetInt32.parseDecimal "+2147483647", 2147483647)
    andalso same (SubsetInt32.parseNatural "00012", 12)
    andalso same (SubsetInt32.parseNatural "0", 0)
    andalso invalid (SubsetInt32.parseNatural "")
    andalso invalid (SubsetInt32.parseNatural "-1")
    andalso invalid (SubsetInt32.parseNatural "+1")
    andalso invalid (SubsetInt32.parseNatural " 1")
    andalso invalid (SubsetInt32.parseNatural "1 ")
    andalso invalid (SubsetInt32.parseDecimal "1x")
    andalso invalid (SubsetInt32.fromString "-")
    andalso overflow (SubsetInt32.parseNatural "2147483648")
    andalso overflow (SubsetInt32.parseDecimal "-2147483649")
    andalso overflow (SubsetInt32.fromString "99999999999999999999999999999999")
  val some = fn (option, expected) => case option of
      SubsetOptionValue.SOME value => value = expected | SubsetOptionValue.NONE => false
  val none = fn option => case option of
      SubsetOptionValue.SOME value => false | SubsetOptionValue.NONE => true
  val real = fn (value : real, expected : real) => value >= expected andalso value <= expected
  val integerOps = SubsetInt32.minimum = ~2147483648 andalso SubsetInt32.maximum = 2147483647
    andalso some (SubsetInt32.checkedAdd (2147483646, 1), 2147483647)
    andalso none (SubsetInt32.checkedAdd (2147483647, 1))
    andalso none (SubsetInt32.checkedAdd (~2147483648, ~1))
    andalso some (SubsetInt32.checkedSub (~2147483647, 1), ~2147483648)
    andalso none (SubsetInt32.checkedSub (~2147483648, 1))
    andalso none (SubsetInt32.checkedSub (0, ~2147483648))
    andalso some (SubsetInt32.checkedMul (46340, 46340), 2147395600)
    andalso none (SubsetInt32.checkedMul (46341, 46341))
    andalso some (SubsetInt32.checkedMul (~65536, 32768), ~2147483648)
    andalso some (SubsetInt32.checkedMul (32768, ~65536), ~2147483648)
    andalso none (SubsetInt32.checkedMul (65536, 32768))
    andalso none (SubsetInt32.checkedMul (~1, ~2147483648))
    andalso some (SubsetInt32.checkedMul (~2147483648, 1), ~2147483648)
    andalso some (SubsetInt32.checkedMul (~7, ~6), 42)
    andalso some (SubsetInt32.checkedMul (0, ~2147483648), 0)
    andalso real (SubsetInt32.toReal64 ~2147483648, ~2147483648.0)
    andalso real (SubsetInt32.toReal64 12, 12.0)
    andalso some (SubsetInt32.fromReal64 ~2147483648.0, ~2147483648)
    andalso some (SubsetInt32.fromReal64 2147483647.0, 2147483647)
    andalso some (SubsetInt32.fromReal64 ~3.0, ~3)
    andalso none (SubsetInt32.fromReal64 2147483648.0)
    andalso none (SubsetInt32.fromReal64 2.5)
    andalso none (SubsetInt32.fromReal64 (0.0 / 0.0))
    andalso none (SubsetInt32.fromReal64 (1.0 / 0.0))
  val padding = same (SubsetStringCvt.padLeft ("a", 4, #"0"), "000a")
    andalso same (SubsetStringCvt.padRight ("a", 4, #"0"), "a000")
    andalso same (SubsetStringCvt.padRight ("ab", 1, #"0"), "ab")
    andalso same (SubsetStringCvt.padLeft ("ab", ~2147483648, #"0"), "ab")
    andalso same (SubsetStringCvt.padRight ("", 2, #"\255"), "\255\255")
  val paths = SubsetList.all ([ ("", ""), ("a", ""), ("a/b", "a"),
      ("/a", "/"), ("/", "/"), ("a/", "a"), ("//a/b", "//a"),
      ("a//b", "a/"), ("///", "//") ], fn (path, expected) => same (SubsetPath.dir path, expected))
  val unicode = case SubsetText.str 129418 of
      SubsetResult.Err error => false
    | SubsetResult.Ok fox =>
        same (SubsetStringCvt.padTextRight (fox, 3, 46), fox ^ "..")
        andalso same (SubsetStringCvt.padTextLeft ("a", 3, 129418), fox ^ fox ^ "a")
        andalso same (SubsetText.size fox, 1)
        andalso same (SubsetText.compare (fox, "a"), SubsetOrder.Greater)
        andalso same (SubsetText.compare (fox, fox), SubsetOrder.Equal)
        andalso same (SubsetPath.dir ("/" ^ fox ^ "/a"), "/" ^ fox)
        andalso same (SubsetText.trim (" " ^ fox ^ "  ", fn c => c = 32), fox)
  val _ = if integers andalso integerOps andalso padding andalso paths andalso unicode
    then print "small source helpers: ok\n" else print "FAILED\n"
end
