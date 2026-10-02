(* Compiler-only compatibility helpers while callers migrate to checked Basis APIs.
   Assertions below rely on validated byte strings and checked/generated lexical bounds. *)
structure CompilerText = struct
  val characters = fn value => let val SubsetResult.Ok bytes = SubsetString.fromNative value in bytes end
  val stringOf = fn bytes => let val SubsetResult.Ok value = SubsetString.toNative bytes in value end
  val size = fn value => SubsetBytes.length (characters value)
  val str = fn c => stringOf [c]
  val explode = characters
  val implode = stringOf
  val map = fn f => fn value => stringOf (SubsetList.map (characters value, f))
  val translate = fn f => fn value =>
    SubsetList.foldLeft (SubsetList.map (characters value, f), "", fn (part, acc) => acc ^ part)
  val escapeSmlChar = fn c => let val SubsetResult.Ok text = SubsetSmlEscape.escapeByte c in text end
  val escapeSmlString = fn value => let val SubsetResult.Ok text = SubsetSmlEscape.escapeString value in text end
  val source = fn value => let val SubsetResult.Ok source = SubsetSource.fromNative value in source end
  val sub = fn (source, index) => let val SubsetResult.Ok c = SubsetSource.at (source, index) in c end
  val substring = fn (source, start, count) =>
    let val SubsetResult.Ok bytes = SubsetSource.slice (source, start, count) in stringOf bytes end
end
