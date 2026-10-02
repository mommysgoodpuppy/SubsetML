(* Portable failure contracts and reader behavior, shared with generated Workman. *)
structure TextBasis = struct
  val fails = fn (result, reason, offset) =>
    case result of
      SubsetResult.Ok value => false
    | SubsetResult.Err (SubsetUnicode.Error (actual, at)) => actual = reason andalso Real.== (at, offset)

  val utf8 = fails (SubsetUtf8.decode [#"\128"], SubsetUnicode.InvalidLeadingByte, 0.0)
    andalso fails (SubsetUtf8.decode [#"a", #"\194"], SubsetUnicode.Truncated, 2.0)
    andalso fails (SubsetUtf8.decode [#"a", #"\194", #"b"], SubsetUnicode.InvalidContinuation, 2.0)
    andalso fails (SubsetUtf8.decode [#"\224", #"\128", #"\128"], SubsetUnicode.Overlong, 0.0)
    andalso fails (SubsetUtf8.decode [#"\237", #"\160", #"\128"], SubsetUnicode.Surrogate, 0.0)
    andalso fails (SubsetUtf8.decode [#"\244", #"\144", #"\128", #"\128"], SubsetUnicode.OutOfRange, 0.0)
    andalso fails (SubsetUtf8.decode [#"\192", #"\128"], SubsetUnicode.InvalidLeadingByte, 0.0)
  val utf16 = fails (SubsetUtf16.decode ([#"a"], SubsetUtf16.LittleEndian), SubsetUnicode.OddLength, 0.0)
    andalso fails (SubsetUtf16.decode ([#"\000", #"\220"], SubsetUtf16.LittleEndian), SubsetUnicode.UnpairedSurrogate, 0.0)
    andalso fails (SubsetUtf16.decode ([#"\000", #"\216"], SubsetUtf16.LittleEndian), SubsetUnicode.Truncated, 2.0)
    andalso fails (SubsetUtf16.decode ([#"\000", #"\216", #"a", #"\000"], SubsetUtf16.LittleEndian), SubsetUnicode.UnpairedSurrogate, 2.0)
    andalso fails (SubsetUtf16.decode ([#"\216", #"\000", #"\000"], SubsetUtf16.BigEndian), SubsetUnicode.OddLength, 2.0)
  val invalid = SubsetList.all ([~1.0, 0.5, 0.0 / 0.0], fn value =>
    fails (SubsetUtf8.encode [65.0, value], SubsetUnicode.InvalidScalar, 1.0)
    andalso fails (SubsetUtf16.encode ([65.0, value], SubsetUtf16.BigEndian), SubsetUnicode.InvalidScalar, 1.0))
    andalso fails (SubsetUtf8.encode [55296.0], SubsetUnicode.Surrogate, 0.0)
    andalso fails (SubsetUtf8.encode [1114112.0], SubsetUnicode.OutOfRange, 0.0)
  val readers =
    case SubsetBytes.reader [#"\000", #"\255"] of
      SubsetResult.Err error => false
    | SubsetResult.Ok reader =>
        Real.== (SubsetBytes.position reader, 0.0) andalso SubsetBytes.peek reader = SOME #"\000"
        andalso (case SubsetBytes.next reader of NONE => false | SOME step =>
          let val (first, rest) = step in first = #"\000" andalso Real.== (SubsetBytes.position rest, 1.0)
          andalso (case SubsetBytes.next rest of NONE => false | SOME step =>
            let val (last, eof) = step in last = #"\255" andalso SubsetBytes.peek eof = NONE
            andalso (case SubsetBytes.next eof of NONE => true | SOME value => false) end) end)
  val slices =
    (case SubsetBytes.slice ([#"a", #"b", #"c"], 1.0, 2.0) of
      SubsetResult.Ok bytes => bytes = [#"b", #"c"] | SubsetResult.Err error => false)
    andalso (case SubsetBytes.at ([], 0.0) of
      SubsetResult.Err SubsetBytes.OutOfBounds => true | SubsetResult.Err error => false | SubsetResult.Ok c => false)
    andalso SubsetList.all ([~1.0, 0.5, 4.0, 0.0 / 0.0, 1.0 / 0.0], fn index =>
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
            Real.== (SubsetSource.length source, 256.0)
            andalso SubsetList.all (SubsetChar.byteChars, fn c =>
              case SubsetChar.toCode c of
                SubsetResult.Err error => false
              | SubsetResult.Ok index => (case SubsetSource.at (source, index) of
                  SubsetResult.Err error => false | SubsetResult.Ok actual => actual = c))
            andalso (case SubsetSource.slice (source, 254.0, 2.0) of
              SubsetResult.Err error => false | SubsetResult.Ok bytes => bytes = [#"\254", #"\255"])
            andalso (case SubsetSource.slice (source, 256.0, 0.0) of
              SubsetResult.Err error => false | SubsetResult.Ok bytes => bytes = [])
            andalso SubsetList.all ([~1.0, 0.5, 256.0, 0.0 / 0.0, 1.0 / 0.0], fn index =>
              case SubsetSource.at (source, index) of
                SubsetResult.Err SubsetBytes.InvalidIndex => true
              | SubsetResult.Err error => false | SubsetResult.Ok c => false))
  val _ = if native andalso utf8 andalso utf16 andalso invalid andalso readers andalso slices
    then print "text contracts: ok\n" else print "FAILED\n"
end
