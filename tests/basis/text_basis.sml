(* Portable failure contracts and reader behavior, shared with generated Workman. *)
structure TextBasis = struct
  open SubsetOptionValue

  val fails = fn (result, reason, offset) =>
    case result of
      SubsetResult.Ok value => false
    | SubsetResult.Err (SubsetUnicode.Error (actual, at)) => actual = reason andalso (at = offset)

  val utf8 = fails (SubsetUtf8.decode [#"\128"], SubsetUnicode.InvalidLeadingByte, 0)
    andalso fails (SubsetUtf8.decode [#"a", #"\194"], SubsetUnicode.Truncated, 2)
    andalso fails (SubsetUtf8.decode [#"a", #"\194", #"b"], SubsetUnicode.InvalidContinuation, 2)
    andalso fails (SubsetUtf8.decode [#"\224", #"\128", #"\128"], SubsetUnicode.Overlong, 0)
    andalso fails (SubsetUtf8.decode [#"\237", #"\160", #"\128"], SubsetUnicode.Surrogate, 0)
    andalso fails (SubsetUtf8.decode [#"\244", #"\144", #"\128", #"\128"], SubsetUnicode.OutOfRange, 0)
    andalso fails (SubsetUtf8.decode [#"\192", #"\128"], SubsetUnicode.InvalidLeadingByte, 0)
  val utf16 = fails (SubsetUtf16.decode ([#"a"], SubsetUtf16.LittleEndian), SubsetUnicode.OddLength, 0)
    andalso fails (SubsetUtf16.decode ([#"\000", #"\220"], SubsetUtf16.LittleEndian), SubsetUnicode.UnpairedSurrogate, 0)
    andalso fails (SubsetUtf16.decode ([#"\000", #"\216"], SubsetUtf16.LittleEndian), SubsetUnicode.Truncated, 2)
    andalso fails (SubsetUtf16.decode ([#"\000", #"\216", #"a", #"\000"], SubsetUtf16.LittleEndian), SubsetUnicode.UnpairedSurrogate, 2)
    andalso fails (SubsetUtf16.decode ([#"\216", #"\000", #"\000"], SubsetUtf16.BigEndian), SubsetUnicode.OddLength, 2)
  val invalid = SubsetList.all ([~1, ~2147483648], fn value =>
    fails (SubsetUtf8.encode [65, value], SubsetUnicode.InvalidScalar, 1)
    andalso fails (SubsetUtf16.encode ([65, value], SubsetUtf16.BigEndian), SubsetUnicode.InvalidScalar, 1))
    andalso fails (SubsetUtf8.encode [55296], SubsetUnicode.Surrogate, 0)
    andalso fails (SubsetUtf8.encode [1114112], SubsetUnicode.OutOfRange, 0)
  val readers =
    case SubsetBytes.reader [#"\000", #"\255"] of
      SubsetResult.Err error => false
    | SubsetResult.Ok reader =>
        (SubsetBytes.position reader = 0) andalso SubsetBytes.peek reader = SOME #"\000"
        andalso (case SubsetBytes.next reader of NONE => false | SOME step =>
          let val (first, rest) = step in first = #"\000" andalso (SubsetBytes.position rest = 1)
          andalso (case SubsetBytes.next rest of NONE => false | SOME step =>
            let val (last, eof) = step in last = #"\255" andalso SubsetBytes.peek eof = NONE
            andalso (case SubsetBytes.next eof of NONE => true | SOME value => false) end) end)
  val slices =
    (case SubsetBytes.slice ([#"a", #"b", #"c"], 1, 2) of
      SubsetResult.Ok bytes => bytes = [#"b", #"c"] | SubsetResult.Err error => false)
    andalso (case SubsetBytes.at ([], 0) of
      SubsetResult.Err SubsetBytes.OutOfBounds => true | SubsetResult.Err error => false | SubsetResult.Ok c => false)
    andalso SubsetList.all ([~1, 4], fn index =>
      case SubsetBytes.splitAt ([#"a", #"b", #"c"], index) of
        SubsetResult.Err SubsetBytes.InvalidIndex => true | SubsetResult.Err error => false | SubsetResult.Ok pair => false)
  val native =
    case SubsetString.toNative SubsetChar.byteChars of
      SubsetResult.Err error => false
    | SubsetResult.Ok value =>
        (case SubsetString.fromNative value of
          SubsetResult.Err error => false | SubsetResult.Ok bytes => bytes = SubsetChar.byteChars)
        andalso (case SubsetSource.fromNative value of
          SubsetResult.Err error => false
        | SubsetResult.Ok source =>
            (SubsetSource.length source = 256)
            andalso SubsetList.all (SubsetChar.byteChars, fn c =>
              case SubsetChar.toCode c of
                SubsetResult.Err error => false
              | SubsetResult.Ok index => (case SubsetSource.at (source, index) of
                  SubsetResult.Err error => false | SubsetResult.Ok actual => actual = c))
            andalso (case SubsetSource.slice (source, 254, 2) of
              SubsetResult.Err error => false | SubsetResult.Ok bytes => bytes = [#"\254", #"\255"])
            andalso (case SubsetSource.slice (source, 256, 0) of
              SubsetResult.Err error => false | SubsetResult.Ok bytes => bytes = [])
            andalso SubsetList.all ([~1, 256], fn index =>
              case SubsetSource.at (source, index) of
                SubsetResult.Err SubsetBytes.InvalidIndex => true
              | SubsetResult.Err error => false | SubsetResult.Ok c => false))
  (* STRING contracts from research/sml-basis-spec/Basis/string.html.
     This suite runs as authored SML, roundtripped SML, and generated WM. *)
  val stringSearch = SubsetList.all (["", "a", "ab", "aba"], fn value =>
    SubsetString.isPrefix (value, "") = SubsetResult.Ok true
    andalso SubsetString.isSuffix (value, "") = SubsetResult.Ok true
    andalso SubsetString.isSubstring (value, "") = SubsetResult.Ok true
    andalso SubsetString.isPrefix (value, value) = SubsetResult.Ok true
    andalso SubsetString.isSuffix (value, value) = SubsetResult.Ok true
    andalso SubsetString.isSubstring (value, value) = SubsetResult.Ok true)
    andalso SubsetString.isPrefix ("abc", "ab") = SubsetResult.Ok true
    andalso SubsetString.isPrefix ("abc", "bc") = SubsetResult.Ok false
    andalso SubsetString.isSuffix ("abc", "bc") = SubsetResult.Ok true
    andalso SubsetString.isSuffix ("abc", "ab") = SubsetResult.Ok false
    andalso SubsetString.isSubstring ("ababac", "abac") = SubsetResult.Ok true
    andalso SubsetString.isSubstring ("ababa", "abac") = SubsetResult.Ok false
    andalso SubsetString.isSubstring ("a", "ab") = SubsetResult.Ok false
    andalso SubsetString.isSubstring ("a\000\255b", "\000\255") = SubsetResult.Ok true
  val stringFields =
    SubsetString.fields ("|abc||def", fn c => c = #"|") = SubsetResult.Ok ["", "abc", "", "def"]
    andalso SubsetString.tokens ("|abc||def", fn c => c = #"|") = SubsetResult.Ok ["abc", "def"]
    andalso SubsetString.fields ("", fn c => true) = SubsetResult.Ok [""]
    andalso SubsetString.tokens ("", fn c => true) = SubsetResult.Ok []
    andalso SubsetString.fields ("||", fn c => c = #"|") = SubsetResult.Ok ["", "", ""]
    andalso SubsetString.tokens ("||", fn c => c = #"|") = SubsetResult.Ok []
    andalso SubsetString.fields ("a\000\255b", fn c => c = #"\000") = SubsetResult.Ok ["a", "\255b"]
    andalso SubsetString.fields ("abc", fn c => false) = SubsetResult.Ok ["abc"]
  val textHelpers =
    (* Construct host text through the boundary so JS and SML use their own encoding. *)
    case SubsetResult.andThen (SubsetUtf8.encode [233, 47, 26481, 47, 129418], SubsetText.fromUtf8) of
      SubsetResult.Err error => false
    | SubsetResult.Ok text =>
      (case SubsetText.fields (text, fn scalar => scalar = 47) of
        SubsetResult.Err error => false
      | SubsetResult.Ok pieces =>
          (case pieces of
            [first, middle, last] =>
              SubsetText.isPrefix (text, first) = SubsetResult.Ok true
              andalso SubsetText.isSuffix (text, last) = SubsetResult.Ok true
              andalso SubsetText.isSubstring (text, middle) = SubsetResult.Ok true
              andalso SubsetText.isPrefix (text, last) = SubsetResult.Ok false
              andalso SubsetText.isSuffix (text, first) = SubsetResult.Ok false
              andalso SubsetText.fields (text, fn scalar => scalar = 129418)
                = SubsetResult.Ok [first ^ "/" ^ middle ^ "/", ""]
              andalso SubsetText.tokens (text, fn scalar => scalar = 129418)
                = SubsetResult.Ok [first ^ "/" ^ middle ^ "/"]
              andalso SubsetString.concatWith (pieces, "/") = text
          | other => false))
  val textEdges = SubsetText.fields ("/a//", fn scalar => scalar = 47)
      = SubsetResult.Ok ["", "a", "", ""]
    andalso SubsetText.tokens ("/a//", fn scalar => scalar = 47) = SubsetResult.Ok ["a"]
    andalso SubsetText.fields ("", fn scalar => true) = SubsetResult.Ok [""]
    andalso SubsetText.tokens ("", fn scalar => true) = SubsetResult.Ok []
    andalso SubsetText.fields ("abc", fn scalar => false) = SubsetResult.Ok ["abc"]
    andalso SubsetText.isPrefix ("", "a") = SubsetResult.Ok false
    andalso SubsetText.isSuffix ("", "") = SubsetResult.Ok true
    andalso SubsetText.isSubstring ("ababac", "abac") = SubsetResult.Ok true
    andalso SubsetText.isSubstring ("ababa", "abac") = SubsetResult.Ok false
  val stringEdits = SubsetString.substring ("a\000\255b", 1, 2) = SubsetResult.Ok "\000\255"
    andalso SubsetString.extract ("abc", 1, NONE) = SubsetResult.Ok "bc"
    andalso SubsetString.extract ("abc", 1, SOME 1) = SubsetResult.Ok "b"
    andalso SubsetString.extract ("abc", 3, NONE) = SubsetResult.Ok ""
    andalso SubsetString.substring ("abc", 3, 0) = SubsetResult.Ok ""
    andalso SubsetString.substring ("", 0, 0) = SubsetResult.Ok ""
    andalso SubsetString.substring ("abc", ~1, 0) = SubsetResult.Err SubsetString.InvalidIndex
    andalso SubsetString.substring ("abc", 0, ~1) = SubsetResult.Err SubsetString.InvalidIndex
    andalso SubsetString.substring ("abc", 3, 1) = SubsetResult.Err SubsetString.InvalidIndex
    andalso SubsetString.substring ("abc", 1, 2147483647) = SubsetResult.Err SubsetString.InvalidIndex
    andalso SubsetString.extract ("abc", 2147483647, NONE) = SubsetResult.Err SubsetString.InvalidIndex
    andalso SubsetString.map ("a|b", fn c => if c = #"|" then #"/" else c) = SubsetResult.Ok "a/b"
    andalso SubsetString.translate ("a|b||", fn c => if c = #"|" then "::" else "") = SubsetResult.Ok "::::::"
    andalso SubsetString.map ("", fn c => #"x") = SubsetResult.Ok ""
    andalso SubsetString.translate ("", fn c => "x") = SubsetResult.Ok ""
  val scalarEdits = case SubsetText.implode [97, 129418, 233] of
      SubsetResult.Err error => false
    | SubsetResult.Ok text =>
        SubsetText.explode text = SubsetResult.Ok [97, 129418, 233]
        andalso (case SubsetText.str 129418 of
          SubsetResult.Err error => false
        | SubsetResult.Ok fox =>
            SubsetText.substring (text, 1, 1) = SubsetResult.Ok fox
            andalso SubsetText.extract (text, 1, SOME 1) = SubsetResult.Ok fox
            andalso SubsetText.map (text, fn scalar => if scalar = 129418 then 47 else scalar)
              = SubsetResult.map (SubsetText.str 233, fn last => "a/" ^ last)
            andalso SubsetText.translate (text, fn scalar => if scalar = 129418 then "XY" else "")
              = SubsetResult.Ok "XY")
        andalso SubsetText.extract (text, 3, NONE) = SubsetResult.Ok ""
        andalso SubsetText.substring (text, 3, 0) = SubsetResult.Ok ""
        andalso SubsetText.substring (text, 0, ~1) = SubsetResult.Err SubsetText.InvalidIndex
        andalso SubsetText.substring (text, ~1, 0) = SubsetResult.Err SubsetText.InvalidIndex
        andalso SubsetText.substring (text, 3, 1) = SubsetResult.Err SubsetText.InvalidIndex
        andalso SubsetText.substring (text, 1, 2147483647) = SubsetResult.Err SubsetText.InvalidIndex
        andalso SubsetText.extract (text, 2147483647, NONE) = SubsetResult.Err SubsetText.InvalidIndex
        andalso fails (SubsetText.map (text, fn scalar => if scalar = 129418 then 55296 else scalar),
          SubsetUnicode.Surrogate, 1)
  val scalarEdges = SubsetText.substring ("", 0, 0) = SubsetResult.Ok ""
    andalso SubsetText.map ("", fn scalar => 55296) = SubsetResult.Ok ""
    andalso SubsetText.translate ("", fn scalar => "x") = SubsetResult.Ok ""
    andalso fails (SubsetText.str 55296, SubsetUnicode.Surrogate, 0)
  val _ = if stringEdits andalso scalarEdits andalso scalarEdges
    andalso stringSearch andalso stringFields andalso textHelpers andalso textEdges
    andalso native andalso utf8 andalso utf16 andalso invalid andalso readers andalso slices
    then print "text contracts: ok\n" else print "FAILED\n"
end
