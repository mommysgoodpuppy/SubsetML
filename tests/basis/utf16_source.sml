(* @subsetml
from "../../src/subset_utf16_source.sml" import * as SubsetUtf16Source;
from "../../src/subset_utf16.sml" import * as SubsetUtf16;
from "../../src/subset_unicode.sml" import * as SubsetUnicode;
from "../../src/subset_result.sml" import * as SubsetResult;
from "../../src/subset_list.sml" import * as SubsetList;
*)
structure Utf16Source = struct
  val same = fn (left, right) =>
    let val rec go = fn
        ([], []) => true
      | (a :: xs, b :: ys) => (a = b) andalso go (xs, ys)
      | ([], rest) => false
      | (rest, []) => false
    in go (left, right) end
  val invalidIndex = fn result =>
    case result of SubsetResult.Err SubsetUtf16Source.InvalidIndex => true
    | SubsetResult.Err error => false | SubsetResult.Ok value => false
  val invalidUnit = fn (result, expected) =>
    case result of SubsetResult.Err (SubsetUtf16Source.InvalidUnit offset) => (offset = expected)
    | SubsetResult.Err error => false | SubsetResult.Ok value => false
  val unicodeError = fn (result, expected, position) =>
    case result of
      SubsetResult.Err (SubsetUtf16Source.UnicodeError (SubsetUnicode.Error (reason, offset))) =>
        reason = expected andalso (offset = position)
    | SubsetResult.Err error => false | SubsetResult.Ok value => false
  val malformedUnits = SubsetList.all ([~1, 65536, 2147483647], fn code =>
    invalidUnit (SubsetUtf16Source.fromUnits [65, code], 1))
  val preserved =
    case SubsetUtf16Source.fromUnits [0, 55296, 65535, 56320] of
      SubsetResult.Err error => false
    | SubsetResult.Ok source =>
        (SubsetUtf16Source.length source = 4)
        andalso same (SubsetUtf16Source.toUnits source, [0, 55296, 65535, 56320])
        andalso unicodeError (SubsetUtf16Source.toUtf8 source, SubsetUnicode.UnpairedSurrogate, 4)
        andalso (case SubsetUtf16Source.peek (source, 0) of
          SOME code => (code = 0) | NONE => false)
        andalso SubsetList.all ([~1, 4], fn index =>
          invalidIndex (SubsetUtf16Source.at (source, index))
          andalso (case SubsetUtf16Source.peek (source, index) of NONE => true | SOME code => false))
        andalso (case SubsetUtf16Source.slice (source, 1, 2) of
          SubsetResult.Err error => false
        | SubsetResult.Ok view =>
            same (SubsetUtf16Source.toUnits view, [55296, 65535])
            andalso (case SubsetUtf16Source.slice (view, 1, 1) of
              SubsetResult.Err error => false
            | SubsetResult.Ok nested => same (SubsetUtf16Source.toUnits nested, [65535])))
        andalso (case SubsetUtf16Source.slice (source, 4, 0) of
          SubsetResult.Err error => false
        | SubsetResult.Ok empty => (SubsetUtf16Source.length empty = 0)
            andalso same (SubsetUtf16Source.toUnits empty, []))
        andalso SubsetList.all ([(~1, 1), (0, ~1),
          (4, 1)], fn bounds =>
            let val (start, count) = bounds in invalidIndex (SubsetUtf16Source.slice (source, start, count)) end)
  val codecs =
    let val bytes = [#"A", #"\226", #"\130", #"\172", #"\240", #"\159", #"\152", #"\128"] in
      case SubsetUtf16Source.fromUtf8 bytes of
        SubsetResult.Err error => false
      | SubsetResult.Ok source =>
          same (SubsetUtf16Source.toUnits source, [65, 8364, 55357, 56832])
          andalso (case SubsetUtf16Source.toUtf8 source of
            SubsetResult.Err error => false | SubsetResult.Ok actual => actual = bytes)
          andalso SubsetList.all ([SubsetUtf16.LittleEndian, SubsetUtf16.BigEndian], fn order =>
            case SubsetUtf16Source.toUtf16Bytes (source, order) of
              SubsetResult.Err error => false
            | SubsetResult.Ok encoded =>
                case SubsetUtf16Source.fromUtf16Bytes (encoded, order) of
                  SubsetResult.Err error => false
                | SubsetResult.Ok decoded => same (SubsetUtf16Source.toUnits source, SubsetUtf16Source.toUnits decoded))
          andalso (case SubsetUtf16Source.slice (source, 2, 1) of
            SubsetResult.Err error => false
          | SubsetResult.Ok high =>
              same (SubsetUtf16Source.toUnits high, [55357])
              andalso unicodeError (SubsetUtf16Source.toScalars high, SubsetUnicode.Truncated, 2))
    end
  val strict =
    unicodeError (SubsetUtf16Source.fromUtf8 [#"\128"], SubsetUnicode.InvalidLeadingByte, 0)
    andalso unicodeError (SubsetUtf16Source.fromScalars [55296], SubsetUnicode.Surrogate, 0)
    andalso unicodeError (SubsetUtf16Source.fromUtf16Bytes ([#"a"], SubsetUtf16.LittleEndian), SubsetUnicode.OddLength, 0)
    andalso (case SubsetUtf16Source.fromUtf16Bytes ([#"\000", #"\216"], SubsetUtf16.LittleEndian) of
      SubsetResult.Err error => false
    | SubsetResult.Ok raw => same (SubsetUtf16Source.toUnits raw, [55296]))
  val native =
    case SubsetUtf16Source.fromNativeUnits "A\000\255" of
      SubsetResult.Err error => false
    | SubsetResult.Ok source => same (SubsetUtf16Source.toUnits source, [65, 0, 255])
  val indexed =
    let
      val rec build = fn (remaining, acc) =>
        if remaining <= 0 then acc else build (remaining - 1, (remaining - 1) :: acc)
      val units = build (2049, [])
    in case SubsetUtf16Source.fromUnits units of
        SubsetResult.Err error => false
      | SubsetResult.Ok source =>
          same (SubsetUtf16Source.toUnits source, units)
          andalso SubsetList.all (units, fn index =>
            case SubsetUtf16Source.at (source, index) of
              SubsetResult.Err error => false | SubsetResult.Ok value => (value = index))
          andalso (case SubsetUtf16Source.slice (source, 1023, 3) of
            SubsetResult.Err error => false
          | SubsetResult.Ok view => same (SubsetUtf16Source.toUnits view, [1023, 1024, 1025]))
    end
  val empty =
    case SubsetUtf16Source.fromUnits [] of
      SubsetResult.Err error => false
    | SubsetResult.Ok source =>
        invalidIndex (SubsetUtf16Source.at (source, 0))
        andalso (case SubsetUtf16Source.slice (source, 0, 0) of
          SubsetResult.Err error => false | SubsetResult.Ok view => same (SubsetUtf16Source.toUnits view, []))
  val _ = print (if malformedUnits andalso preserved andalso codecs andalso strict andalso native andalso indexed andalso empty
    then "UTF-16 source contracts: ok\n" else "UTF-16 source contracts: FAILED\n")
end
