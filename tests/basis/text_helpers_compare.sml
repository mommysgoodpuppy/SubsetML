(* Native-only oracle: SML Basis use here verifies the portable implementations;
   this fixture is not part of the library or its runtime requirements. *)
local
  val values = ["", "a", "b", "ab", "aba", "ababac", "|abc||def", "||", "a|", "\000\255", "x\000\255y"]
  val delimiter = fn c => c = #"|" orelse c = #"\000"
  val strings = List.all (fn value =>
    SubsetString.fields (value, delimiter) = SubsetResult.Ok (String.fields delimiter value)
    andalso SubsetString.tokens (value, delimiter) = SubsetResult.Ok (String.tokens delimiter value)
    andalso List.all (fn pattern =>
      SubsetString.isPrefix (value, pattern) = SubsetResult.Ok (String.isPrefix pattern value)
      andalso SubsetString.isSuffix (value, pattern) = SubsetResult.Ok (String.isSuffix pattern value)
      andalso SubsetString.isSubstring (value, pattern) = SubsetResult.Ok (String.isSubstring pattern value)) values) values
  val byteMap = fn c => if c = #"|" then #"/" else c
  val byteTranslate = fn c => if c = #"|" then "::" else String.str c
  val ranges = [~2147483648, ~1, 0, 1, 2, 3, 6, 2147483647]
  val edits = List.all (fn value =>
    SubsetString.map (value, byteMap) = SubsetResult.Ok (String.map byteMap value)
    andalso SubsetString.translate (value, byteTranslate) = SubsetResult.Ok (String.translate byteTranslate value)
    andalso List.all (fn start =>
      let val suffix = (SubsetResult.Ok (String.extract (value, start, NONE))
            handle Subscript => SubsetResult.Err SubsetString.InvalidIndex)
      in SubsetString.extract (value, start, SubsetOptionValue.NONE) = suffix
        andalso List.all (fn count =>
          let val expected = (SubsetResult.Ok (String.substring (value, start, count))
                handle Subscript => SubsetResult.Err SubsetString.InvalidIndex)
          in SubsetString.substring (value, start, count) = expected
            andalso SubsetString.extract (value, start, SubsetOptionValue.SOME count) = expected end) ranges
      end) ranges) values
  val integerInputs = ["", "-", "~", "+", "  12tail", "123", "000", "-0", "~12", "+7",
    "2147483647", "2147483648", "-2147483648", "-2147483649", "\t+123abc", "abc", "9.9"]
  val integerOracle = List.all (fn text =>
    let val expected = (case Int32.fromString text of
          NONE => SubsetResult.Err SubsetInt.InvalidInteger
        | SOME value => SubsetResult.Ok (Int32.toInt value))
          handle Overflow => SubsetResult.Err SubsetInt.Overflow
    in SubsetInt.fromString text = expected end) integerInputs
  val paddingOracle = List.all (fn text => List.all (fn width =>
    SubsetStringCvt.padLeft (text, width, #" ") = SubsetResult.Ok (StringCvt.padLeft #" " width text)
    andalso SubsetStringCvt.padRight (text, width, #"0") = SubsetResult.Ok (StringCvt.padRight #"0" width text))
      [~2147483648, ~1, 0, 1, 2, 12]) values
  val visited = ref ([] : int list)
  val delimiter = fn scalar => (visited := scalar :: !visited; scalar = 47)
  val malformed = ["\128", "a\192\128", "\237\160\128", "\244\144\128\128"]
  val rejected = List.all (fn value =>
    not (SubsetResult.isOk (SubsetText.isPrefix (value, "")))
    andalso not (SubsetResult.isOk (SubsetText.isSuffix (value, "")))
    andalso not (SubsetResult.isOk (SubsetText.isSubstring (value, "")))
    andalso not (SubsetResult.isOk (SubsetText.isPrefix ("", value)))
    andalso not (SubsetResult.isOk (SubsetText.isSuffix ("", value)))
    andalso not (SubsetResult.isOk (SubsetText.isSubstring ("", value)))
    andalso not (SubsetResult.isOk (SubsetText.fields (value, delimiter)))
    andalso not (SubsetResult.isOk (SubsetText.tokens (value, delimiter)))
    andalso not (SubsetResult.isOk (SubsetText.substring (value, 0, 0)))
    andalso not (SubsetResult.isOk (SubsetText.extract (value, 0, SubsetOptionValue.NONE)))
    andalso not (SubsetResult.isOk (SubsetText.map (value, fn scalar => (visited := scalar :: !visited; scalar))))
    andalso not (SubsetResult.isOk (SubsetText.translate (value, fn scalar => (visited := scalar :: !visited; ""))))) malformed
in
  val _ = if integerOracle andalso paddingOracle andalso edits andalso strings andalso rejected andalso null (!visited) then ()
    else raise Fail "text helper SML oracle / validation before callbacks"
end
