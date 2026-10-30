(* Portable contracts exercised as SML, roundtripped SML and generated WM. *)
structure SmallPortable = struct
  val same = fn (result, expected) => case result of
      SubsetResult.Ok value => value = expected | SubsetResult.Err error => false
  val overflow = fn result => case result of
      SubsetResult.Err SubsetInt.Overflow => true | other => false
  val invalid = fn result => case result of
      SubsetResult.Err SubsetInt.InvalidInteger => true | other => false
  val integers = same (SubsetInt.fromString " \t~12tail", ~12)
    andalso same (SubsetInt.fromString "+12.5", 12)
    andalso same (SubsetInt.fromString "-2147483648", ~2147483648)
    andalso same (SubsetInt.parseDecimal "~2147483648", ~2147483648)
    andalso same (SubsetInt.parseDecimal "+2147483647", 2147483647)
    andalso same (SubsetInt.parseNatural "00012", 12)
    andalso same (SubsetInt.parseNatural "0", 0)
    andalso invalid (SubsetInt.parseNatural "")
    andalso invalid (SubsetInt.parseNatural "-1")
    andalso invalid (SubsetInt.parseNatural "+1")
    andalso invalid (SubsetInt.parseNatural " 1")
    andalso invalid (SubsetInt.parseNatural "1 ")
    andalso invalid (SubsetInt.parseDecimal "1x")
    andalso invalid (SubsetInt.fromString "-")
    andalso overflow (SubsetInt.parseNatural "2147483648")
    andalso overflow (SubsetInt.parseDecimal "-2147483649")
    andalso overflow (SubsetInt.fromString "99999999999999999999999999999999")
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
  val _ = if integers andalso padding andalso paths andalso unicode
    then print "small source helpers: ok\n" else print "FAILED\n"
end
