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
      | (a :: xs, b :: ys) => Real.== (a, b) andalso go (xs, ys)
      | ([], rest) => false
      | (rest, []) => false
    in go (left, right) end
  val invalidIndex = fn result =>
    case result of SubsetResult.Err SubsetUtf16Source.InvalidIndex => true
    | SubsetResult.Err error => false | SubsetResult.Ok value => false
  val invalidUnit = fn (result, expected) =>
    case result of SubsetResult.Err (SubsetUtf16Source.InvalidUnit offset) => Real.== (offset, expected)
    | SubsetResult.Err error => false | SubsetResult.Ok value => false
  val unicodeError = fn (result, expected, position) =>
    case result of
      SubsetResult.Err (SubsetUtf16Source.UnicodeError (SubsetUnicode.Error (reason, offset))) =>
        reason = expected andalso Real.== (offset, position)
    | SubsetResult.Err error => false | SubsetResult.Ok value => false
  val malformedUnits = SubsetList.all ([~1.0, 65536.0, 0.5, 0.0 / 0.0, 1.0 / 0.0], fn code =>
    invalidUnit (SubsetUtf16Source.fromUnits [65.0, code], 1.0))
  val preserved =
    case SubsetUtf16Source.fromUnits [0.0, 55296.0, 65535.0, 56320.0] of
      SubsetResult.Err error => false
    | SubsetResult.Ok source =>
        Real.== (SubsetUtf16Source.length source, 4.0)
        andalso same (SubsetUtf16Source.toUnits source, [0.0, 55296.0, 65535.0, 56320.0])
        andalso unicodeError (SubsetUtf16Source.toUtf8 source, SubsetUnicode.UnpairedSurrogate, 4.0)
        andalso (case SubsetUtf16Source.peek (source, 0.0) of
          SOME code => Real.== (code, 0.0) | NONE => false)
        andalso SubsetList.all ([~1.0, 0.5, 4.0, 0.0 / 0.0, 1.0 / 0.0], fn index =>
          invalidIndex (SubsetUtf16Source.at (source, index))
          andalso (case SubsetUtf16Source.peek (source, index) of NONE => true | SOME code => false))
        andalso (case SubsetUtf16Source.slice (source, 1.0, 2.0) of
          SubsetResult.Err error => false
        | SubsetResult.Ok view =>
            same (SubsetUtf16Source.toUnits view, [55296.0, 65535.0])
            andalso (case SubsetUtf16Source.slice (view, 1.0, 1.0) of
              SubsetResult.Err error => false
            | SubsetResult.Ok nested => same (SubsetUtf16Source.toUnits nested, [65535.0])))
        andalso (case SubsetUtf16Source.slice (source, 4.0, 0.0) of
          SubsetResult.Err error => false
        | SubsetResult.Ok empty => Real.== (SubsetUtf16Source.length empty, 0.0)
            andalso same (SubsetUtf16Source.toUnits empty, []))
        andalso SubsetList.all ([(~1.0, 1.0), (0.5, 1.0), (0.0, 0.5), (0.0, ~1.0),
          (4.0, 1.0), (0.0, 0.0 / 0.0)], fn bounds =>
            let val (start, count) = bounds in invalidIndex (SubsetUtf16Source.slice (source, start, count)) end)
  val codecs =
    let val bytes = [#"A", #"\226", #"\130", #"\172", #"\240", #"\159", #"\152", #"\128"] in
      case SubsetUtf16Source.fromUtf8 bytes of
        SubsetResult.Err error => false
      | SubsetResult.Ok source =>
          same (SubsetUtf16Source.toUnits source, [65.0, 8364.0, 55357.0, 56832.0])
          andalso (case SubsetUtf16Source.toUtf8 source of
            SubsetResult.Err error => false | SubsetResult.Ok actual => actual = bytes)
          andalso SubsetList.all ([SubsetUtf16.LittleEndian, SubsetUtf16.BigEndian], fn order =>
            case SubsetUtf16Source.toUtf16Bytes (source, order) of
              SubsetResult.Err error => false
            | SubsetResult.Ok encoded =>
                case SubsetUtf16Source.fromUtf16Bytes (encoded, order) of
                  SubsetResult.Err error => false
                | SubsetResult.Ok decoded => same (SubsetUtf16Source.toUnits source, SubsetUtf16Source.toUnits decoded))
          andalso (case SubsetUtf16Source.slice (source, 2.0, 1.0) of
            SubsetResult.Err error => false
          | SubsetResult.Ok high =>
              same (SubsetUtf16Source.toUnits high, [55357.0])
              andalso unicodeError (SubsetUtf16Source.toScalars high, SubsetUnicode.Truncated, 2.0))
    end
  val strict =
    unicodeError (SubsetUtf16Source.fromUtf8 [#"\128"], SubsetUnicode.InvalidLeadingByte, 0.0)
    andalso unicodeError (SubsetUtf16Source.fromScalars [55296.0], SubsetUnicode.Surrogate, 0.0)
    andalso unicodeError (SubsetUtf16Source.fromUtf16Bytes ([#"a"], SubsetUtf16.LittleEndian), SubsetUnicode.OddLength, 0.0)
    andalso (case SubsetUtf16Source.fromUtf16Bytes ([#"\000", #"\216"], SubsetUtf16.LittleEndian) of
      SubsetResult.Err error => false
    | SubsetResult.Ok raw => same (SubsetUtf16Source.toUnits raw, [55296.0]))
  val native =
    case SubsetUtf16Source.fromNativeUnits "A\000\255" of
      SubsetResult.Err error => false
    | SubsetResult.Ok source => same (SubsetUtf16Source.toUnits source, [65.0, 0.0, 255.0])
  val indexed =
    let
      val rec build = fn (remaining, acc) =>
        if remaining <= 0.0 then acc else build (remaining - 1.0, (remaining - 1.0) :: acc)
      val units = build (2049.0, [])
    in case SubsetUtf16Source.fromUnits units of
        SubsetResult.Err error => false
      | SubsetResult.Ok source =>
          same (SubsetUtf16Source.toUnits source, units)
          andalso SubsetList.all (units, fn index =>
            case SubsetUtf16Source.at (source, index) of
              SubsetResult.Err error => false | SubsetResult.Ok value => Real.== (value, index))
          andalso (case SubsetUtf16Source.slice (source, 1023.0, 3.0) of
            SubsetResult.Err error => false
          | SubsetResult.Ok view => same (SubsetUtf16Source.toUnits view, [1023.0, 1024.0, 1025.0]))
    end
  val empty =
    case SubsetUtf16Source.fromUnits [] of
      SubsetResult.Err error => false
    | SubsetResult.Ok source =>
        invalidIndex (SubsetUtf16Source.at (source, 0.0))
        andalso (case SubsetUtf16Source.slice (source, 0.0, 0.0) of
          SubsetResult.Err error => false | SubsetResult.Ok view => same (SubsetUtf16Source.toUnits view, []))
  val _ = print (if malformedUnits andalso preserved andalso codecs andalso strict andalso native andalso indexed andalso empty
    then "UTF-16 source contracts: ok\n" else "UTF-16 source contracts: FAILED\n")
end
