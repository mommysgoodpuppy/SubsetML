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
  val real = fn (value : real, expected : real) => value >= expected andalso value <= expected
  val integerOps = SubsetInt32.minimum = ~2147483648 andalso SubsetInt32.maximum = 2147483647
    andalso same (SubsetInt32.checkedAdd (2147483646, 1), 2147483647)
    andalso overflow (SubsetInt32.checkedAdd (2147483647, 1))
    andalso overflow (SubsetInt32.checkedAdd (~2147483648, ~1))
    andalso same (SubsetInt32.checkedSub (~2147483647, 1), ~2147483648)
    andalso overflow (SubsetInt32.checkedSub (~2147483648, 1))
    andalso overflow (SubsetInt32.checkedSub (0, ~2147483648))
    andalso same (SubsetInt32.checkedMul (46340, 46340), 2147395600)
    andalso overflow (SubsetInt32.checkedMul (46341, 46341))
    andalso same (SubsetInt32.checkedMul (~65536, 32768), ~2147483648)
    andalso same (SubsetInt32.checkedMul (32768, ~65536), ~2147483648)
    andalso overflow (SubsetInt32.checkedMul (65536, 32768))
    andalso overflow (SubsetInt32.checkedMul (~1, ~2147483648))
    andalso same (SubsetInt32.checkedMul (~2147483648, 1), ~2147483648)
    andalso same (SubsetInt32.checkedMul (~7, ~6), 42)
    andalso same (SubsetInt32.checkedMul (0, ~2147483648), 0)
    andalso real (SubsetInt32.toReal64 ~2147483648, ~2147483648.0)
    andalso real (SubsetInt32.toReal64 12, 12.0)
    andalso same (SubsetInt32.fromReal64 ~2147483648.0, ~2147483648)
    andalso same (SubsetInt32.fromReal64 2147483647.0, 2147483647)
    andalso same (SubsetInt32.fromReal64 ~3.0, ~3)
    andalso overflow (SubsetInt32.fromReal64 2147483648.0)
    andalso invalid (SubsetInt32.fromReal64 2.5)
    andalso invalid (SubsetInt32.fromReal64 (0.0 / 0.0))
    andalso invalid (SubsetInt32.fromReal64 (1.0 / 0.0))
  val appendMath : string SubsetNumeric.arithmetic = {
    zero = "", one = "", add = fn (a, b) => a ^ b, mul = fn (a, b) => a ^ b
  }
  val arithmetic = SubsetList.sumWith ([1, 2, 3], SubsetInt32.carrier) = 6
    andalso SubsetList.sumWith ([], SubsetInt32.math) = 0
    andalso SubsetList.productWith ([2, 3, 4], SubsetInt32.math) = 24
    andalso SubsetList.productWith ([], SubsetInt32.carrier) = 1
    andalso SubsetList.sumWith (["a", "b", "c"], appendMath) = "abc"
  val carrierLoops = SubsetMonad.traverse ([1, 2, 3], SubsetResult.carrier,
      fn n => SubsetResult.Ok (n * 2)) = SubsetResult.Ok [2, 4, 6]
    andalso SubsetMonad.loop (0, SubsetResult.carrier,
      fn n => SubsetResult.Ok (if n = 200000 then SubsetMonad.Stop n else SubsetMonad.Continue (n + 1)))
      = SubsetResult.Ok 200000
    andalso SubsetResult.loop (0, fn n =>
      if n = 2 then SubsetResult.Err "stop" else SubsetResult.Ok (SubsetMonad.Continue (n + 1)))
      = SubsetResult.Err "stop"
  val generated = SubsetList.unfold (["a", "b", "c"], fn state =>
      case state of [] => SubsetOptionValue.NONE
      | value :: rest => SubsetOptionValue.SOME (value, rest)) = ["a", "b", "c"]
    andalso SubsetList.unfold (false, fn state =>
      if state then SubsetOptionValue.SOME ("unexpected", false) else SubsetOptionValue.NONE) = []
    andalso SubsetInt32.range (~2, 2) = [~2, ~1, 0, 1, 2]
    andalso SubsetInt32.range (3, 2) = []
    andalso SubsetInt32.range (2147483646, 2147483647) = [2147483646, 2147483647]
    andalso SubsetInt32.range (~2147483648, ~2147483647) = [~2147483648, ~2147483647]
    andalso SubsetInt32.range (2147483647, 2147483647) = [2147483647]
    andalso SubsetInt32.foldRange (3, 5, [], fn (value, acc) => value :: acc) = [5, 4, 3]
    andalso SubsetInt32.foldRange (2147483647, ~2147483648, "empty",
      fn (value, acc) => "unexpected callback") = "empty"
    andalso SubsetInt32.foldRange (2147483647, 2147483647, 0, fn (value, acc) => acc + 1) = 1
    andalso SubsetInt32.foldRange (1, 100000, 0, fn (value, acc) => acc + 1) = 100000
  val padding = same (SubsetStringCvt.padLeft32 ("a", 4, #"0"), "000a")
    andalso same (SubsetStringCvt.padRight32 ("a", 4, #"0"), "a000")
    andalso same (SubsetStringCvt.padRight32 ("ab", 1, #"0"), "ab")
    andalso same (SubsetStringCvt.padLeft32 ("ab", ~2147483648, #"0"), "ab")
    andalso same (SubsetStringCvt.padRight32 ("", 2, #"\255"), "\255\255")
  val paths = SubsetList.all ([ ("", ""), ("a", ""), ("a/b", "a"),
      ("/a", "/"), ("/", "/"), ("a/", "a"), ("//a/b", "//a"),
      ("a//b", "a/"), ("///", "//") ], fn (path, expected) => same (SubsetPath.dir path, expected))
  val unicode = case SubsetText.str 129418 of
      SubsetResult.Err error => false
    | SubsetResult.Ok fox =>
        same (SubsetStringCvt.padTextRight32 (fox, 3, 46), fox ^ "..")
        andalso same (SubsetStringCvt.padTextLeft32 ("a", 3, 129418), fox ^ fox ^ "a")
        andalso same (SubsetText.size32 fox, 1)
        andalso same (SubsetText.compare (fox, "a"), SubsetOrder.Greater)
        andalso same (SubsetText.compare (fox, fox), SubsetOrder.Equal)
        andalso same (SubsetPath.dir ("/" ^ fox ^ "/a"), "/" ^ fox)
        andalso same (SubsetText.trim (" " ^ fox ^ "  ", fn c => c = 32), fox)
  val _ = if integers andalso integerOps andalso arithmetic andalso carrierLoops andalso generated andalso padding andalso paths andalso unicode
    then print "small source helpers: ok\n" else print "FAILED\n"
end
